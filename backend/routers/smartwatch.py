# Smartwatch Sync API
# Apple Watch, WearOS, Fitbit, Garmin integration

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from uuid import UUID
from pydantic import BaseModel
from datetime import datetime, timedelta

from database import get_db
from dependencies import get_current_active_user, require_premium
import models
from models_premium import SmartwatchConnection, BiometricData, WearableDevice

router = APIRouter(prefix="/smartwatch", tags=["smartwatch"])


# MARK: - Schemas

class ConnectDeviceRequest(BaseModel):
    device_type: str  # "apple_watch", "wear_os", "fitbit", "garmin"
    device_name: Optional[str] = None
    device_id: Optional[str] = None
    access_token: Optional[str] = None
    refresh_token: Optional[str] = None


class DeviceConnectionResponse(BaseModel):
    id: str
    device_type: str
    device_name: Optional[str]
    is_connected: bool
    last_sync: Optional[str]
    created_at: str

    class Config:
        from_attributes = True


class BiometricDataRequest(BaseModel):
    date: str  # ISO format
    resting_heart_rate: Optional[int] = None
    avg_heart_rate: Optional[int] = None
    max_heart_rate: Optional[int] = None
    heart_rate_variability: Optional[int] = None
    sleep_duration: Optional[int] = None
    deep_sleep: Optional[int] = None
    rem_sleep: Optional[int] = None
    light_sleep: Optional[int] = None
    sleep_quality_score: Optional[float] = None
    steps: Optional[int] = None
    active_calories: Optional[int] = None
    total_calories: Optional[int] = None
    exercise_minutes: Optional[int] = None
    recovery_score: Optional[float] = None
    training_strain: Optional[float] = None


class BiometricDataResponse(BaseModel):
    id: str
    date: str
    resting_heart_rate: Optional[int]
    avg_heart_rate: Optional[int]
    max_heart_rate: Optional[int]
    heart_rate_variability: Optional[int]
    sleep_duration: Optional[int]
    deep_sleep: Optional[int]
    rem_sleep: Optional[int]
    light_sleep: Optional[int]
    sleep_quality_score: Optional[float]
    steps: Optional[int]
    active_calories: Optional[int]
    total_calories: Optional[int]
    exercise_minutes: Optional[int]
    recovery_score: Optional[float]
    training_strain: Optional[float]
    day_strain: Optional[float]
    readiness_score: Optional[float]
    fatigue_level: Optional[str]
    performance_prediction: Optional[float]
    created_at: str

    class Config:
        from_attributes = True


class RecoveryStatusResponse(BaseModel):
    """Current recovery status for display"""
    recovery_score: Optional[float]
    readiness_score: Optional[float]
    fatigue_level: str
    sleep_quality: Optional[float]
    hrv_status: str  # "optimal", "normal", "low", "very_low"
    recommendation: str
    last_updated: Optional[str]


# MARK: - Device Connection

@router.post("/connect", response_model=DeviceConnectionResponse, dependencies=[Depends(require_premium)])
async def connect_device(
    request: ConnectDeviceRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Connect smartwatch device.

    Supported: Apple Watch, WearOS, Fitbit, Garmin, Whoop, Oura
    """

    # Check if already connected
    existing = db.query(SmartwatchConnection).filter(
        SmartwatchConnection.user_id == current_user.id
    ).first()

    if existing:
        # Update existing connection
        existing.device_type = WearableDevice(request.device_type)
        existing.device_name = request.device_name
        existing.device_id = request.device_id
        existing.access_token = request.access_token
        existing.refresh_token = request.refresh_token
        existing.is_connected = True
        existing.last_sync = datetime.utcnow()

        db.commit()
        db.refresh(existing)
        connection = existing
    else:
        # Create new connection
        connection = SmartwatchConnection(
            user_id=current_user.id,
            device_type=WearableDevice(request.device_type),
            device_name=request.device_name,
            device_id=request.device_id,
            access_token=request.access_token,
            refresh_token=request.refresh_token,
            is_connected=True,
            last_sync=datetime.utcnow()
        )
        db.add(connection)
        db.commit()
        db.refresh(connection)

    return DeviceConnectionResponse(
        id=str(connection.id),
        device_type=connection.device_type.value,
        device_name=connection.device_name,
        is_connected=connection.is_connected,
        last_sync=connection.last_sync.isoformat() if connection.last_sync else None,
        created_at=connection.created_at.isoformat() if isinstance(connection.created_at, datetime) else str(connection.created_at)
    )


@router.get("/connection", response_model=DeviceConnectionResponse, dependencies=[Depends(require_premium)])
async def get_connection(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get current smartwatch connection"""

    connection = db.query(SmartwatchConnection).filter(
        SmartwatchConnection.user_id == current_user.id
    ).first()

    if not connection:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No smartwatch connected"
        )

    return DeviceConnectionResponse(
        id=str(connection.id),
        device_type=connection.device_type.value,
        device_name=connection.device_name,
        is_connected=connection.is_connected,
        last_sync=connection.last_sync.isoformat() if connection.last_sync else None,
        created_at=connection.created_at.isoformat() if isinstance(connection.created_at, datetime) else str(connection.created_at)
    )


@router.delete("/disconnect", dependencies=[Depends(require_premium)])
async def disconnect_device(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Disconnect smartwatch"""

    connection = db.query(SmartwatchConnection).filter(
        SmartwatchConnection.user_id == current_user.id
    ).first()

    if not connection:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No smartwatch connected"
        )

    db.delete(connection)
    db.commit()

    return {"message": "Smartwatch disconnected successfully"}


# MARK: - Biometric Data

@router.post("/sync", response_model=BiometricDataResponse, dependencies=[Depends(require_premium)])
async def sync_biometric_data(
    data: BiometricDataRequest,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """
    Sync biometric data from smartwatch.

    Called by iOS/Android app after fetching from HealthKit/Google Fit/etc.
    """

    # Parse date
    data_date = datetime.fromisoformat(data.date.replace('Z', '+00:00'))

    # Check if data exists for this date
    existing = db.query(BiometricData).filter(
        BiometricData.user_id == current_user.id,
        BiometricData.date == data_date
    ).first()

    if existing:
        # Update existing
        if data.resting_heart_rate: existing.resting_heart_rate = data.resting_heart_rate
        if data.avg_heart_rate: existing.avg_heart_rate = data.avg_heart_rate
        if data.max_heart_rate: existing.max_heart_rate = data.max_heart_rate
        if data.heart_rate_variability: existing.heart_rate_variability = data.heart_rate_variability
        if data.sleep_duration: existing.sleep_duration = data.sleep_duration
        if data.deep_sleep: existing.deep_sleep = data.deep_sleep
        if data.rem_sleep: existing.rem_sleep = data.rem_sleep
        if data.light_sleep: existing.light_sleep = data.light_sleep
        if data.sleep_quality_score: existing.sleep_quality_score = data.sleep_quality_score
        if data.steps: existing.steps = data.steps
        if data.active_calories: existing.active_calories = data.active_calories
        if data.total_calories: existing.total_calories = data.total_calories
        if data.exercise_minutes: existing.exercise_minutes = data.exercise_minutes
        if data.recovery_score: existing.recovery_score = data.recovery_score
        if data.training_strain: existing.training_strain = data.training_strain

        db.commit()
        db.refresh(existing)
        biometric = existing
    else:
        # Create new
        biometric = BiometricData(
            user_id=current_user.id,
            date=data_date,
            resting_heart_rate=data.resting_heart_rate,
            avg_heart_rate=data.avg_heart_rate,
            max_heart_rate=data.max_heart_rate,
            heart_rate_variability=data.heart_rate_variability,
            sleep_duration=data.sleep_duration,
            deep_sleep=data.deep_sleep,
            rem_sleep=data.rem_sleep,
            light_sleep=data.light_sleep,
            sleep_quality_score=data.sleep_quality_score,
            steps=data.steps,
            active_calories=data.active_calories,
            total_calories=data.total_calories,
            exercise_minutes=data.exercise_minutes,
            recovery_score=data.recovery_score,
            training_strain=data.training_strain
        )
        db.add(biometric)
        db.commit()
        db.refresh(biometric)

    # Calculate AI metrics (would be done by AI service in production)
    calculate_ai_metrics(biometric, db)

    # Update last sync time
    connection = db.query(SmartwatchConnection).filter(
        SmartwatchConnection.user_id == current_user.id
    ).first()
    if connection:
        connection.last_sync = datetime.utcnow()
        db.commit()

    return BiometricDataResponse(
        id=str(biometric.id),
        date=biometric.date.isoformat(),
        resting_heart_rate=biometric.resting_heart_rate,
        avg_heart_rate=biometric.avg_heart_rate,
        max_heart_rate=biometric.max_heart_rate,
        heart_rate_variability=biometric.heart_rate_variability,
        sleep_duration=biometric.sleep_duration,
        deep_sleep=biometric.deep_sleep,
        rem_sleep=biometric.rem_sleep,
        light_sleep=biometric.light_sleep,
        sleep_quality_score=biometric.sleep_quality_score,
        steps=biometric.steps,
        active_calories=biometric.active_calories,
        total_calories=biometric.total_calories,
        exercise_minutes=biometric.exercise_minutes,
        recovery_score=biometric.recovery_score,
        training_strain=biometric.training_strain,
        day_strain=biometric.day_strain,
        readiness_score=biometric.readiness_score,
        fatigue_level=biometric.fatigue_level,
        performance_prediction=biometric.performance_prediction,
        created_at=biometric.created_at.isoformat()
    )


@router.get("/data/recent", response_model=List[BiometricDataResponse], dependencies=[Depends(require_premium)])
async def get_recent_biometric_data(
    days: int = 7,
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get recent biometric data"""

    start_date = datetime.utcnow() - timedelta(days=days)

    data_list = db.query(BiometricData).filter(
        BiometricData.user_id == current_user.id,
        BiometricData.date >= start_date
    ).order_by(BiometricData.date.desc()).all()

    return [
        BiometricDataResponse(
            id=str(d.id),
            date=d.date.isoformat(),
            resting_heart_rate=d.resting_heart_rate,
            avg_heart_rate=d.avg_heart_rate,
            max_heart_rate=d.max_heart_rate,
            heart_rate_variability=d.heart_rate_variability,
            sleep_duration=d.sleep_duration,
            deep_sleep=d.deep_sleep,
            rem_sleep=d.rem_sleep,
            light_sleep=d.light_sleep,
            sleep_quality_score=d.sleep_quality_score,
            steps=d.steps,
            active_calories=d.active_calories,
            total_calories=d.total_calories,
            exercise_minutes=d.exercise_minutes,
            recovery_score=d.recovery_score,
            training_strain=d.training_strain,
            day_strain=d.day_strain,
            readiness_score=d.readiness_score,
            fatigue_level=d.fatigue_level,
            performance_prediction=d.performance_prediction,
            created_at=d.created_at.isoformat()
        )
        for d in data_list
    ]


@router.get("/recovery-status", response_model=RecoveryStatusResponse, dependencies=[Depends(require_premium)])
async def get_recovery_status(
    current_user: models.User = Depends(get_current_active_user),
    db: Session = Depends(get_db)
):
    """Get current recovery status for display"""

    # Get today's data
    today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

    biometric = db.query(BiometricData).filter(
        BiometricData.user_id == current_user.id,
        BiometricData.date >= today
    ).first()

    if not biometric:
        return RecoveryStatusResponse(
            recovery_score=None,
            readiness_score=None,
            fatigue_level="unknown",
            sleep_quality=None,
            hrv_status="unknown",
            recommendation="Connect your smartwatch to track recovery",
            last_updated=None
        )

    # Determine HRV status
    hrv_status = "unknown"
    if biometric.heart_rate_variability:
        if biometric.heart_rate_variability >= 60:
            hrv_status = "optimal"
        elif biometric.heart_rate_variability >= 40:
            hrv_status = "normal"
        elif biometric.heart_rate_variability >= 20:
            hrv_status = "low"
        else:
            hrv_status = "very_low"

    # Generate recommendation
    recommendation = generate_recovery_recommendation(biometric)

    return RecoveryStatusResponse(
        recovery_score=biometric.recovery_score,
        readiness_score=biometric.readiness_score,
        fatigue_level=biometric.fatigue_level or "unknown",
        sleep_quality=biometric.sleep_quality_score,
        hrv_status=hrv_status,
        recommendation=recommendation,
        last_updated=biometric.created_at.isoformat()
    )


# MARK: - Helper Functions

def calculate_ai_metrics(biometric: BiometricData, db: Session):
    """Calculate AI-derived metrics"""

    # Readiness score (0-100)
    readiness = 50.0

    if biometric.recovery_score:
        readiness += (biometric.recovery_score - 50) * 0.4

    if biometric.sleep_quality_score:
        readiness += (biometric.sleep_quality_score - 50) * 0.3

    if biometric.heart_rate_variability:
        hrv_contribution = min((biometric.heart_rate_variability - 30) * 0.5, 20)
        readiness += hrv_contribution

    biometric.readiness_score = max(0, min(100, readiness))

    # Fatigue level
    if readiness < 30:
        biometric.fatigue_level = "very_high"
    elif readiness < 50:
        biometric.fatigue_level = "high"
    elif readiness < 70:
        biometric.fatigue_level = "medium"
    else:
        biometric.fatigue_level = "low"

    # Performance prediction
    biometric.performance_prediction = (readiness - 50) / 5.0  # -10 to +10

    db.commit()


def generate_recovery_recommendation(biometric: BiometricData) -> str:
    """Generate recovery recommendation"""

    if not biometric.readiness_score:
        return "Sync your smartwatch for personalized recommendations"

    if biometric.readiness_score >= 80:
        return "Excellent recovery! Perfect day for intense training or competition."
    elif biometric.readiness_score >= 60:
        return "Good recovery. Moderate to high intensity training recommended."
    elif biometric.readiness_score >= 40:
        return "Fair recovery. Consider light training or active recovery."
    else:
        return "Poor recovery. Rest day recommended. Focus on sleep and nutrition."
