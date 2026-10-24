"""Graph engine for indoor navigation routing and accessibility path calculation."""
import json
import math
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple
import networkx as nx

from app.models import UserProfile, NavigationStep, RouteResponse, NodeInfo, BuildingSummary


class IndoorGraphEngine:
    """Loads building topology, applies mobility filters, and calculates accessible routes."""

    def __init__(self, data_path: Optional[str] = None):
        if data_path is None:
            import os
            env_path = os.getenv("BUILDING_DATA_PATH")
            if env_path:
                self.data_path = env_path
            else:
                default_path = Path(__file__).parent / "data" / "building_mock.json"
                self.data_path = str(default_path)
        else:
            self.data_path = data_path

        self.building_id: str = ""
        self.building_name: str = ""
        self.version: str = "1.0.0"
        self.floors: List[int] = []
        self.nodes_dict: Dict[str, Dict[str, Any]] = {}
        self.raw_edges: List[Dict[str, Any]] = []
        self.alias_map: Dict[str, str] = {}
        self.base_graph = nx.Graph()

        self._load_data()

    def _load_data(self) -> None:
        """Parses the JSON building definition and populates lookup indices."""
        with open(self.data_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.building_id = data.get("building_id", "default_building")
        self.building_name = data.get("name", "Indoor Facility")
        self.version = data.get("version", "1.0.0")
        self.floors = data.get("floors", [1])
        self.raw_edges = data.get("edges", [])

        # Index nodes and aliases
        for node in data.get("nodes", []):
            nid = node["id"]
            self.nodes_dict[nid] = node

            # Direct mapping
            self.alias_map[nid.lower()] = nid
            self.alias_map[node["label"].lower()] = nid

            # Alternative sign matches (OCR keywords)
            for sign in node.get("signs", []):
                self.alias_map[sign.strip().lower()] = nid

            self.base_graph.add_node(
                nid,
                label=node["label"],
                floor=node["floor"],
                x=node["x"],
                y=node["y"],
                type=node["type"],
                signs=node.get("signs", [])
            )

        # Index base edges
        for edge in self.raw_edges:
            self.base_graph.add_edge(
                edge["source"],
                edge["target"],
                distance_meters=float(edge["distance_meters"]),
                has_stairs=bool(edge.get("has_stairs", False)),
                width_meters=float(edge.get("width_meters", 1.5)),
                door_type=edge.get("door_type", "open")
            )

    def resolve_node_id(self, query: str) -> Optional[str]:
        """Resolves a room label, OCR text string, or node identifier to a canonical node ID."""
        if not query:
            return None
        cleaned = query.strip().lower()

        # 1. Exact match in alias lookup
        if cleaned in self.alias_map:
            return self.alias_map[cleaned]

        # 2. Case-insensitive node id check
        for nid in self.nodes_dict:
            if nid.lower() == cleaned:
                return nid

        # 3. Substring / Token matching for human labels
        for alias, nid in self.alias_map.items():
            if cleaned in alias or alias in cleaned:
                return nid

        return None

    def build_filtered_graph(self, profile: UserProfile) -> nx.Graph:
        """Constructs an active navigation graph enforcing accessibility constraints."""
        filtered = nx.Graph()

        # Copy all nodes
        for nid, data in self.base_graph.nodes(data=True):
            filtered.add_node(nid, **data)

        # Filter edges based on user capabilities
        for u, v, data in self.base_graph.edges(data=True):
            has_stairs = data.get("has_stairs", False)
            width = data.get("width_meters", 1.5)

            # Wheelchair or stair avoidance rule
            if (profile.wheelchair_user or profile.avoid_stairs) and has_stairs:
                continue

            # Minimum passable doorway / corridor clearance
            if width < profile.min_door_width:
                continue

            filtered.add_edge(u, v, **data)

        return filtered

    def _calculate_relative_turn(
        self,
        prev_node: Dict[str, Any],
        curr_node: Dict[str, Any],
        next_node: Dict[str, Any]
    ) -> Tuple[str, str]:
        """Calculates 2D planar bearing change and returns (turn_type, ble_command)."""
        v1_x = curr_node["x"] - prev_node["x"]
        v1_y = curr_node["y"] - prev_node["y"]

        v2_x = next_node["x"] - curr_node["x"]
        v2_y = next_node["y"] - curr_node["y"]

        # Vector cross and dot products
        cross = v1_x * v2_y - v1_y * v2_x
        dot = v1_x * v2_x + v1_y * v2_y

        angle_deg = math.degrees(math.atan2(cross, dot))

        # Thresholds for planar turns
        if angle_deg > 35.0:
            return "LEFT", "L"
        elif angle_deg < -35.0:
            return "RIGHT", "R"
        else:
            return "STRAIGHT", "F"

    def compute_route(
        self,
        start_query: str,
        dest_query: str,
        profile: Optional[UserProfile] = None
    ) -> RouteResponse:
        """Calculates optimal path and formats turn-by-turn steps."""
        if profile is None:
            profile = UserProfile()

        start_node_id = self.resolve_node_id(start_query)
        dest_node_id = self.resolve_node_id(dest_query)

        if not start_node_id:
            raise ValueError(f"Unknown starting location or sign code: '{start_query}'")
        if not dest_node_id:
            raise ValueError(f"Unknown destination room or sign label: '{dest_query}'")

        if start_node_id == dest_node_id:
            dest_info = self.nodes_dict[dest_node_id]
            arrival_step = NavigationStep(
                step_index=0,
                from_node=start_node_id,
                to_node=dest_node_id,
                instruction=f"You are already at {dest_info['label']}.",
                turn_type="ARRIVE",
                ble_command="S",
                distance_meters=0.0,
                floor=dest_info["floor"],
                landmark_hint=dest_info.get("signs", [dest_info["label"]])[0]
            )
            return RouteResponse(
                building_id=self.building_id,
                start_node_id=start_node_id,
                destination_node_id=dest_node_id,
                destination_label=dest_info["label"],
                total_distance_meters=0.0,
                estimated_time_seconds=0,
                accessible=True,
                route_nodes=[start_node_id],
                steps=[arrival_step]
            )

        active_graph = self.build_filtered_graph(profile)

        if not active_graph.has_node(start_node_id) or not active_graph.has_node(dest_node_id):
            raise ValueError("Endpoint node was filtered out by accessibility restrictions.")

        try:
            path = nx.shortest_path(
                active_graph,
                source=start_node_id,
                target=dest_node_id,
                weight="distance_meters"
            )
        except nx.NetworkXNoPath as exc:
            raise RuntimeError(
                f"No accessible route between '{start_node_id}' and '{dest_node_id}' under user mobility constraints."
            ) from exc

        # Build turn-by-turn guidance steps
        steps: List[NavigationStep] = []
        total_dist = 0.0

        for i in range(len(path) - 1):
            curr_id = path[i]
            next_id = path[i + 1]

            curr_node = self.nodes_dict[curr_id]
            next_node = self.nodes_dict[next_id]

            edge_data = active_graph.get_edge_data(curr_id, next_id)
            segment_dist = edge_data["distance_meters"]
            total_dist += segment_dist

            landmark = (
                next_node.get("signs", [next_node["label"]])[0]
                if next_node.get("signs")
                else next_node["label"]
            )

            # Check for vertical floor transitions (elevators or stairs)
            if curr_node["floor"] != next_node["floor"]:
                is_lift = (curr_node["type"] == "elevator" or next_node["type"] == "elevator")
                target_floor = next_node["floor"]
                if target_floor > curr_node["floor"]:
                    turn_type = "ELEVATOR_UP" if is_lift else "STAIRS_UP"
                    vehicle = "elevator" if is_lift else "stairs"
                    instruction = f"Take the {vehicle} up to Floor {target_floor}."
                else:
                    turn_type = "ELEVATOR_DOWN" if is_lift else "STAIRS_DOWN"
                    vehicle = "elevator" if is_lift else "stairs"
                    instruction = f"Take the {vehicle} down to Floor {target_floor}."
                ble_cmd = "F"
            elif i == 0:
                # First step heading
                turn_type = "STRAIGHT"
                ble_cmd = "F"
                instruction = f"Proceed forward {segment_dist:.1f} meters towards {next_node['label']}."
            else:
                # Mid-route turn calculation
                prev_id = path[i - 1]
                prev_node = self.nodes_dict[prev_id]
                turn_type, ble_cmd = self._calculate_relative_turn(prev_node, curr_node, next_node)

                if turn_type == "LEFT":
                    instruction = f"Turn left and walk {segment_dist:.1f} meters towards {next_node['label']}."
                elif turn_type == "RIGHT":
                    instruction = f"Turn right and walk {segment_dist:.1f} meters towards {next_node['label']}."
                else:
                    instruction = f"Continue straight for {segment_dist:.1f} meters towards {next_node['label']}."

            steps.append(
                NavigationStep(
                    step_index=i,
                    from_node=curr_id,
                    to_node=next_id,
                    instruction=instruction,
                    turn_type=turn_type,
                    ble_command=ble_cmd,
                    distance_meters=round(segment_dist, 1),
                    floor=curr_node["floor"],
                    landmark_hint=landmark
                )
            )

        # Final arrival step
        dest_node = self.nodes_dict[dest_node_id]
        steps.append(
            NavigationStep(
                step_index=len(steps),
                from_node=path[-1],
                to_node=dest_node_id,
                instruction=f"You have arrived at your destination: {dest_node['label']}.",
                turn_type="ARRIVE",
                ble_command="S",
                distance_meters=0.0,
                floor=dest_node["floor"],
                landmark_hint=dest_node["label"]
            )
        )

        speed = max(0.1, profile.walking_speed_mps)
        est_seconds = int(total_dist / speed)

        return RouteResponse(
            building_id=self.building_id,
            start_node_id=start_node_id,
            destination_node_id=dest_node_id,
            destination_label=dest_node["label"],
            total_distance_meters=round(total_dist, 1),
            estimated_time_seconds=est_seconds,
            accessible=True,
            route_nodes=path,
            steps=steps
        )

    def get_building_summary(self) -> BuildingSummary:
        """Returns metadata about the active building map."""
        return BuildingSummary(
            building_id=self.building_id,
            name=self.building_name,
            version=self.version,
            floors=self.floors,
            total_nodes=len(self.nodes_dict),
            total_edges=len(self.raw_edges)
        )

    def list_nodes(self) -> List[NodeInfo]:
        """Returns all indexed landmarks and rooms for search and OCR matching."""
        result: List[NodeInfo] = []
        for n in self.nodes_dict.values():
            result.append(
                NodeInfo(
                    id=n["id"],
                    label=n["label"],
                    floor=n["floor"],
                    x=n["x"],
                    y=n["y"],
                    type=n["type"],
                    signs=n.get("signs", [])
                )
            )
        return result
