"""
Test cases for FastAPI application
"""

import pytest
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)


def test_read_root():
    """Test root endpoint"""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert "message" in data
    assert "{{PROJECT_NAME}}" in data["message"]


def test_health_check():
    """Test health check endpoint"""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert data["service"] == "{{PROJECT_NAME}}"


def test_get_items_empty():
    """Test getting items when none exist"""
    response = client.get("/items")
    assert response.status_code == 200
    assert response.json() == []


def test_create_item():
    """Test creating a new item"""
    item_data = {
        "name": "Test Item",
        "description": "A test item",
        "price": 10.99,
        "tax": 1.10
    }
    
    response = client.post("/items", json=item_data)
    assert response.status_code == 200
    
    data = response.json()
    assert data["name"] == item_data["name"]
    assert data["description"] == item_data["description"]
    assert data["price"] == item_data["price"]
    assert data["tax"] == item_data["tax"]
    assert data["total"] == item_data["price"] + item_data["tax"]
    assert "id" in data


def test_get_item():
    """Test getting a specific item"""
    # First create an item
    item_data = {
        "name": "Get Test Item",
        "description": "An item for get testing",
        "price": 15.99,
        "tax": 1.60
    }
    
    create_response = client.post("/items", json=item_data)
    created_item = create_response.json()
    item_id = created_item["id"]
    
    # Now get the item
    response = client.get(f"/items/{item_id}")
    assert response.status_code == 200
    
    data = response.json()
    assert data["id"] == item_id
    assert data["name"] == item_data["name"]


def test_get_nonexistent_item():
    """Test getting an item that doesn't exist"""
    response = client.get("/items/999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Item not found"


def test_update_item():
    """Test updating an existing item"""
    # First create an item
    item_data = {
        "name": "Update Test Item",
        "description": "An item for update testing",
        "price": 20.99,
        "tax": 2.10
    }
    
    create_response = client.post("/items", json=item_data)
    created_item = create_response.json()
    item_id = created_item["id"]
    
    # Update the item
    updated_data = {
        "name": "Updated Test Item",
        "description": "An updated item",
        "price": 25.99,
        "tax": 2.60
    }
    
    response = client.put(f"/items/{item_id}", json=updated_data)
    assert response.status_code == 200
    
    data = response.json()
    assert data["id"] == item_id
    assert data["name"] == updated_data["name"]
    assert data["price"] == updated_data["price"]


def test_delete_item():
    """Test deleting an item"""
    # First create an item
    item_data = {
        "name": "Delete Test Item",
        "price": 30.99
    }
    
    create_response = client.post("/items", json=item_data)
    created_item = create_response.json()
    item_id = created_item["id"]
    
    # Delete the item
    response = client.delete(f"/items/{item_id}")
    assert response.status_code == 200
    assert "deleted successfully" in response.json()["message"]
    
    # Verify item is gone
    get_response = client.get(f"/items/{item_id}")
    assert get_response.status_code == 404


def test_item_validation():
    """Test item validation"""
    # Test with missing required fields
    invalid_item = {
        "description": "Missing name and price"
    }
    
    response = client.post("/items", json=invalid_item)
    assert response.status_code == 422  # Validation error


def test_get_all_items():
    """Test getting all items"""
    # Create multiple items
    items_data = [
        {"name": "Item 1", "price": 10.00},
        {"name": "Item 2", "price": 20.00},
        {"name": "Item 3", "price": 30.00}
    ]
    
    created_ids = []
    for item_data in items_data:
        response = client.post("/items", json=item_data)
        created_ids.append(response.json()["id"])
    
    # Get all items
    response = client.get("/items")
    assert response.status_code == 200
    
    items = response.json()
    assert len(items) >= len(items_data)
    
    # Check that our created items are in the response
    item_names = [item["name"] for item in items]
    for item_data in items_data:
        assert item_data["name"] in item_names