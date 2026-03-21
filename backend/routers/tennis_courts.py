"""
API endpoints for Tennis Court locations
"""
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import and_, func
from typing import List, Optional
import models
import schemas
from database import get_db
from dependencies import get_current_active_user
import math

router = APIRouter(prefix="/tennis-courts", tags=["tennis_courts"])


def calculate_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """
    Calculate distance between two coordinates using Haversine formula
    Returns distance in miles
    """
    R = 3959  # Earth's radius in miles

    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)

    a = math.sin(delta_lat / 2) ** 2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c


@router.get("/nearby", response_model=List[schemas.TennisCourtResponse])
async def get_nearby_courts(
    latitude: float = Query(..., description="User's latitude"),
    longitude: float = Query(..., description="User's longitude"),
    radius_miles: float = Query(10.0, description="Search radius in miles", ge=1.0, le=50.0),
    limit: int = Query(20, description="Maximum number of courts to return", ge=1, le=100),
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get tennis courts near a location

    Tennis-specific requirement: Returns real tennis court locations with venue access info
    """
    # Fetch all courts (in production, use spatial DB queries for efficiency)
    courts = db.query(models.TennisCourt).all()

    # Calculate distances and filter by radius
    courts_with_distance = []
    for court in courts:
        distance = calculate_distance(latitude, longitude, court.latitude, court.longitude)
        if distance <= radius_miles:
            courts_with_distance.append((court, distance))

    # Sort by distance
    courts_with_distance.sort(key=lambda x: x[1])

    # Return limited results with distance info
    results = []
    for court, distance in courts_with_distance[:limit]:
        court_data = schemas.TennisCourtResponse.from_orm(court)
        court_data.distance_miles = round(distance, 2)
        results.append(court_data)

    return results


@router.get("/{court_id}", response_model=schemas.TennisCourtResponse)
async def get_court_details(
    court_id: str,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Get detailed information about a specific tennis court
    """
    court = db.query(models.TennisCourt).filter(models.TennisCourt.id == court_id).first()

    if not court:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Tennis court not found"
        )

    return schemas.TennisCourtResponse.from_orm(court)


@router.post("/add", response_model=schemas.TennisCourtResponse)
async def add_tennis_court(
    court_data: schemas.TennisCourtCreate,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Add a new tennis court to the database (community-sourced)
    Admin verification required before showing to all users
    """
    # Check for duplicate (same name and address)
    existing = db.query(models.TennisCourt).filter(
        and_(
            models.TennisCourt.name == court_data.name,
            models.TennisCourt.address == court_data.address
        )
    ).first()

    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This tennis court already exists in the database"
        )

    court = models.TennisCourt(
        name=court_data.name,
        address=court_data.address,
        city=court_data.city,
        state=court_data.state,
        postal_code=court_data.postal_code,
        latitude=court_data.latitude,
        longitude=court_data.longitude,
        venue_type=court_data.venue_type,
        requires_reservation=court_data.requires_reservation,
        requires_membership=court_data.requires_membership,
        hourly_rate=court_data.hourly_rate,
        currency=court_data.currency,
        surface_type=court_data.surface_type,
        num_courts=court_data.num_courts,
        has_lights=court_data.has_lights,
        indoor=court_data.indoor,
        phone=court_data.phone,
        website=court_data.website,
        hours_of_operation=court_data.hours_of_operation,
        is_verified=False,  # Requires admin verification
        added_by=current_user.id
    )

    db.add(court)
    db.commit()
    db.refresh(court)

    return schemas.TennisCourtResponse.from_orm(court)


@router.get("/search/by-city", response_model=List[schemas.TennisCourtResponse])
async def search_courts_by_city(
    city: str = Query(..., description="City name to search"),
    state: Optional[str] = Query(None, description="State (optional)"),
    limit: int = Query(20, ge=1, le=100),
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Search for tennis courts by city/state
    """
    query = db.query(models.TennisCourt).filter(
        func.lower(models.TennisCourt.city) == city.lower()
    )

    if state:
        query = query.filter(func.lower(models.TennisCourt.state) == state.lower())

    courts = query.limit(limit).all()

    return [schemas.TennisCourtResponse.from_orm(court) for court in courts]
