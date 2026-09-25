from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field
from .readiness import ReadinessProfileSchema, ObservationResponse, ReadinessPredictionResponse

class PersonalizationSettingsSchema(BaseModel):
    user_id: str
    personalization_enabled: bool
    context_capture_enabled: bool
    use_task_history: bool
    use_focus_feedback: bool
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class PersonalizationSettingsUpdate(BaseModel):
    personalization_enabled: Optional[bool] = None
    context_capture_enabled: Optional[bool] = None
    use_task_history: Optional[bool] = None
    use_focus_feedback: Optional[bool] = None

class EvaluationMetric(BaseModel):
    category: str
    total_samples: int
    completion_rate: float
    avg_duration_ratio: float # actual / planned

class PersonalizationEvaluationResponse(BaseModel):
    total_evaluations: int
    brier_calibration_score: float # lower is better (0.0 = perfect calibration)
    overall_completion_rate: float
    overall_postponement_rate: float
    avg_duration_ratio: float
    accuracy_by_time_window: Dict[str, float]
    metrics_by_task_type: List[EvaluationMetric]
    model_version: str

class PersonalizationResetResponse(BaseModel):
    status: str
    message: str
    deleted_observations: int
    deleted_predictions: int
    deleted_evaluations: int

class PersonalizationExportResponse(BaseModel):
    user_id: str
    exported_at: datetime
    profile: Optional[ReadinessProfileSchema] = None
    settings: Optional[PersonalizationSettingsSchema] = None
    observations_count: int
    observations: List[ObservationResponse] = []
    predictions_count: int
    predictions: List[ReadinessPredictionResponse] = []
    evaluations_count: int
