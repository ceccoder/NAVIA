"""Pytest test cases for NAVIA indoor router and accessibility engine."""
import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_check():
    """Verify backend health endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "NAVIA-Backend"
    assert data["building_loaded"] == "campus_med_center"


def test_list_buildings_and_nodes():
    """Verify metadata listings for building topology and rooms."""
    resp_b = client.get("/api/v1/buildings")
    assert resp_b.status_code == 200
    buildings = resp_b.json()
    assert len(buildings) >= 1
    assert buildings[0]["building_id"] == "campus_med_center"

    resp_n = client.get("/api/v1/nodes")
    assert resp_n.status_code == 200
    nodes = resp_n.json()
    assert len(nodes) >= 10
    node_ids = [n["id"] for n in nodes]
    assert "L1_ENTRANCE" in node_ids
    assert "L2_ROOM_214" in node_ids


def test_standard_route_calculation():
    """Verify route from Main Entrance to Room 214 for an able-bodied user."""
    payload = {
        "building_id": "campus_med_center",
        "start_node_id": "L1_ENTRANCE",
        "destination_label": "Room 214",
        "user_profile": {
            "wheelchair_user": False,
            "min_door_width": 0.8
        }
    }
    response = client.post("/api/v1/route", json=payload)
    assert response.status_code == 200
    data = response.json()

    assert data["start_node_id"] == "L1_ENTRANCE"
    assert data["destination_node_id"] == "L2_ROOM_214"
    assert data["total_distance_meters"] > 0
    assert len(data["steps"]) >= 2

    # Check BLE commands and instructions
    first_step = data["steps"][0]
    assert first_step["ble_command"] in ["F", "L", "R", "S"]
    assert "Proceed forward" in first_step["instruction"]

    last_step = data["steps"][-1]
    assert last_step["turn_type"] == "ARRIVE"
    assert last_step["ble_command"] == "S"


def test_wheelchair_accessibility_stairs_filtering():
    """Verify that a wheelchair user is routed strictly via the Elevator, never stairs."""
    payload = {
        "building_id": "campus_med_center",
        "start_node_id": "L1_ENTRANCE",
        "destination_label": "Room 214",
        "user_profile": {
            "wheelchair_user": True,
            "avoid_stairs": True,
            "min_door_width": 1.0
        }
    }
    response = client.post("/api/v1/route", json=payload)
    assert response.status_code == 200
    data = response.json()

    nodes_in_path = data["route_nodes"]
    assert "L1_STAIRS" not in nodes_in_path, "Stairs node must not be in wheelchair route"
    assert "L2_STAIRS" not in nodes_in_path, "Stairs node must not be in wheelchair route"
    assert "L1_ELEVATOR" in nodes_in_path, "Elevator node must be chosen for wheelchair user"
    assert "L2_ELEVATOR" in nodes_in_path, "Elevator node must be chosen for wheelchair user"

    # Confirm step instructions mention elevator
    step_types = [s["turn_type"] for s in data["steps"]]
    assert "ELEVATOR_UP" in step_types


def test_door_width_accessibility_barrier():
    """Verify that a room with a narrow door (0.75m) is blocked if wheelchair user requires > 0.8m."""
    # Room 215 has 0.75m doorway
    blocked_payload = {
        "building_id": "campus_med_center",
        "start_node_id": "L2_LOBBY",
        "destination_label": "Room 215",
        "user_profile": {
            "wheelchair_user": True,
            "min_door_width": 0.9  # Wider than 0.75m
        }
    }
    resp_blocked = client.post("/api/v1/route", json=blocked_payload)
    assert resp_blocked.status_code == 422  # No accessible route found

    # Should succeed when door width requirement is satisfied
    allowed_payload = {
        "building_id": "campus_med_center",
        "start_node_id": "L2_LOBBY",
        "destination_label": "Room 215",
        "user_profile": {
            "wheelchair_user": False,
            "min_door_width": 0.7
        }
    }
    resp_allowed = client.post("/api/v1/route", json=allowed_payload)
    assert resp_allowed.status_code == 200
    assert resp_allowed.json()["destination_node_id"] == "L2_ROOM_215"


def test_ocr_sign_recognition_anchor():
    """Verify OCR detected text (e.g. 'MAIN ENTRANCE' and '214') successfully anchors navigation."""
    payload = {
        "building_id": "campus_med_center",
        "start_node_id": "MAIN ENTRANCE",  # Scanned OCR sign text
        "destination_label": "214",         # OCR sign text for Room 214
        "user_profile": {
            "wheelchair_user": False
        }
    }
    response = client.post("/api/v1/route", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["start_node_id"] == "L1_ENTRANCE"
    assert data["destination_node_id"] == "L2_ROOM_214"


def test_unknown_location_error_handling():
    """Verify 404 response on unknown start node or missing room."""
    payload_bad_start = {
        "building_id": "campus_med_center",
        "start_node_id": "NON_EXISTENT_CORRIDOR",
        "destination_label": "Room 214"
    }
    resp = client.post("/api/v1/route", json=payload_bad_start)
    assert resp.status_code == 404

    payload_bad_dest = {
        "building_id": "campus_med_center",
        "start_node_id": "L1_ENTRANCE",
        "destination_label": "Room 999 NonExistent"
    }
    resp = client.post("/api/v1/route", json=payload_bad_dest)
    assert resp.status_code == 404


def test_same_start_and_destination():
    """Verify 0m route when already at destination."""
    payload = {
        "building_id": "campus_med_center",
        "start_node_id": "L1_LOBBY",
        "destination_label": "Lobby Information Desk"
    }
    response = client.post("/api/v1/route", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["total_distance_meters"] == 0.0
    assert len(data["steps"]) == 1
    assert data["steps"][0]["turn_type"] == "ARRIVE"
    assert data["steps"][0]["ble_command"] == "S"
