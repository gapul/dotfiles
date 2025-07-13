"""
FastAPI Application - {{PROJECT_NAME}}
Modern Python web API with automatic OpenAPI documentation
"""

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional
import uvicorn

# Initialize FastAPI app
app = FastAPI(
    title="{{PROJECT_NAME}}",
    description="Modern Python web API built with FastAPI",
    version="0.1.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Pydantic models
class Item(BaseModel):
    id: Optional[int] = None
    name: str
    description: Optional[str] = None
    price: float
    tax: Optional[float] = None

class ItemResponse(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    price: float
    tax: Optional[float] = None
    total: float

# In-memory storage (replace with database in production)
items_db: List[Item] = []
next_id = 1

# Routes
@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "message": "Welcome to {{PROJECT_NAME}} API",
        "docs": "/docs",
        "redoc": "/redoc",
        "version": "0.1.0"
    }

@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "service": "{{PROJECT_NAME}}"}

@app.get("/items", response_model=List[ItemResponse])
async def get_items():
    """Get all items"""
    return [
        ItemResponse(
            id=item.id,
            name=item.name,
            description=item.description,
            price=item.price,
            tax=item.tax,
            total=item.price + (item.tax or 0)
        )
        for item in items_db
    ]

@app.get("/items/{item_id}", response_model=ItemResponse)
async def get_item(item_id: int):
    """Get a specific item by ID"""
    for item in items_db:
        if item.id == item_id:
            return ItemResponse(
                id=item.id,
                name=item.name,
                description=item.description,
                price=item.price,
                tax=item.tax,
                total=item.price + (item.tax or 0)
            )
    raise HTTPException(status_code=404, detail="Item not found")

@app.post("/items", response_model=ItemResponse)
async def create_item(item: Item):
    """Create a new item"""
    global next_id
    item.id = next_id
    next_id += 1
    items_db.append(item)
    
    return ItemResponse(
        id=item.id,
        name=item.name,
        description=item.description,
        price=item.price,
        tax=item.tax,
        total=item.price + (item.tax or 0)
    )

@app.put("/items/{item_id}", response_model=ItemResponse)
async def update_item(item_id: int, updated_item: Item):
    """Update an existing item"""
    for i, item in enumerate(items_db):
        if item.id == item_id:
            updated_item.id = item_id
            items_db[i] = updated_item
            return ItemResponse(
                id=updated_item.id,
                name=updated_item.name,
                description=updated_item.description,
                price=updated_item.price,
                tax=updated_item.tax,
                total=updated_item.price + (updated_item.tax or 0)
            )
    raise HTTPException(status_code=404, detail="Item not found")

@app.delete("/items/{item_id}")
async def delete_item(item_id: int):
    """Delete an item"""
    for i, item in enumerate(items_db):
        if item.id == item_id:
            deleted_item = items_db.pop(i)
            return {"message": f"Item '{deleted_item.name}' deleted successfully"}
    raise HTTPException(status_code=404, detail="Item not found")

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)