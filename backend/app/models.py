"""Data models and schemas for NAVIA indoor navigation system."""
from typing import List, Optional
from pydantic import BaseModel, Field


class UserProfile(BaseModel):
    """User accessibility and mobility preferences."""
    wheelchair_user: bool = Field(default=False, description="Whether routing must avoid all stairs and step obstacles")
    visually_impaired: bool = Field(default=True, description="Enables explicit tactile and audio landmark prompts")
    min_door_width: float = Field(default=0.8, ge=0.5, le=3.0, description="Minimum passable door/corridor width in meters")
    avoid_stairs: bool = Field(default=False, description="Flag to avoid stairs even if wheelchair_user is false")
    walking_speed_mps: float = Field(default=1.0, gt=0.1, le=3.0, description="Estimated walking speed in meters/second")


class RouteRequest(BaseModel):
    """Payload for route computation."""
    building_id: str = Field(default="campus_med_center", description="Identifier of the target building graph")
    start_node_id: str = Field(..., description="ID or anchor code of the starting node (e.g. L1_ENTRANCE or detected sign)")
    destination_label: str = Field(..., description="Target room number or name (e.g. 'Room 214', 'Pharmacy', 'Restroom')")
    user_profile: UserProfile = Field(default_factory=UserProfile, description="User mobility profile")


class NavigationStep(BaseModel):
    """Discrete turn-by-turn guidance directive."""
    step_index: int = Field(..., description="Sequential step ordering starting at 0")
    from_node: str = Field(..., description="Source node ID")
    to_node: str = Field(..., description="Target node ID")
    instruction: str = Field(..., description="Vocalized text-to-speech navigation guidance")
    turn_type: str = Field(..., description="Classification: STRAIGHT, LEFT, RIGHT, ELEVATOR_UP, ELEVATOR_DOWN, STAIRS_UP, STAIRS_DOWN, ARRIVE")
    ble_command: str = Field(..., description="Single-byte command for wearable haptics: 'L', 'R', 'S', or 'F'")
    distance_meters: float = Field(..., description="Segment length in meters")
    floor: int = Field(..., description="Building level/floor of the segment")
    landmark_hint: Optional[str] = Field(default=None, description="Physical sign or visual landmark hint along segment")


class RouteResponse(BaseModel):
    """Full path routing response."""
    building_id: str
    start_node_id: str
    destination_node_id: str
    destination_label: str
    total_distance_meters: float
    estimated_time_seconds: int
    accessible: bool
    route_nodes: List[str]
    steps: List[NavigationStep]


class NodeInfo(BaseModel):
    """Public descriptor for building nodes (used for autocompletion and OCR sign mapping)."""
    id: str
    label: str
    floor: int
    x: float
    y: float
    type: str
    signs: List[str] = Field(default_factory=list)


class BuildingSummary(BaseModel):
    """Summary metadata of an indoor building map."""
    building_id: str
    name: str
    version: str
    floors: List[int]
    total_nodes: int
    total_edges: int
