import os
import asyncio
from typing import List
from fastapi import FastAPI, HTTPException, Request, status
from pydantic import BaseModel, EmailStr
from sqlalchemy import Table, Column, Integer, String, Text, MetaData, select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncEngine
from sqlalchemy.exc import IntegrityError
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from prometheus_client import CollectorRegistry
from prometheus_client import multiprocess

# OpenTelemetry
from opentelemetry import trace
from opentelemetry.trace import SpanKind
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.sdk._logs import LoggerProvider
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry._logs import set_logger_provider
from opentelemetry._logs import get_logger
from opentelemetry.sdk._logs import LogRecord
try:
    from opentelemetry.sdk._logs import SeverityNumber
except ImportError:
    try:
        from opentelemetry.sdk._logs._internal.severity import SeverityNumber
    except ImportError:
        from opentelemetry._logs.severity import SeverityNumber

from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry import metrics


DATABASE_URL = os.getenv("DATABASE_URL", "postgresql+asyncpg://postgres:postgres@postgres:5432/commentsdb")
OTEL_ENDPOINT = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "otel-collector:4317")

resource = Resource.create({"service.name": "comments-api"})

metric_exporter = OTLPMetricExporter(
    endpoint=OTEL_ENDPOINT,
    insecure=True,
)

metric_reader = PeriodicExportingMetricReader(metric_exporter)

provider = MeterProvider(resource=resource, metric_readers=[metric_reader])
metrics.set_meter_provider(provider)

meter = metrics.get_meter("comments_api_meter")

# Custom Metrics
REQUEST_COUNT = meter.create_counter(
    "api_request_count",
    unit="1",
    description="Total number of API requests",
)

REQUEST_LATENCY = meter.create_histogram(
    "api_request_latency_seconds",
    unit="s",
    description="Latency of API requests",
)

# Prometheus metrics
REQUEST_COUNT_PROM = Counter(
    "api_requests_total",
    "Total HTTP requests",
    ["method", "endpoint", "http_status"],
)

REQUEST_LATENCY_PROM = Histogram(
"api_request_duration_seconds",
"Request latency (seconds)",
["method", "endpoint"],
)

# Configure OTel structured logs
logger_provider = LoggerProvider(resource=resource)
set_logger_provider(logger_provider)
otlp_log_exporter = OTLPLogExporter(
    endpoint=OTEL_ENDPOINT,
    insecure=True
)
logger_provider.add_log_record_processor(
    BatchLogRecordProcessor(otlp_log_exporter)
)
LoggingInstrumentor().instrument(
    logger_provider=logger_provider,
    set_logging_format=True
)
logger = get_logger("comments_api")

# OpenTelemetry setup TRACE
provider = TracerProvider()
otlp_exporter = OTLPSpanExporter(endpoint=OTEL_ENDPOINT, insecure=True)
provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# FastAPI app
app = FastAPI(title="Comments API")
FastAPIInstrumentor.instrument_app(app, tracer_provider=provider)

# Database table definition
metadata = MetaData()
comments_table = Table(
    "comments",
    metadata,
    Column("id", Integer, primary_key=True, autoincrement=True),
    Column("email", String(320), nullable=False),
    Column("comment", Text, nullable=False),
    Column("content_id", Integer, nullable=False, index=True),
)

engine: AsyncEngine = create_async_engine(DATABASE_URL, future=True)
# Pydantic models
class CommentIn(BaseModel):
    email: EmailStr
    comment: str
    content_id: int

class CommentOut(BaseModel):
    id: int
    email: EmailStr
    comment: str
    content_id: int

# Startup: create table if not exists
@app.on_event("startup")
async def startup():
    async with engine.begin() as conn:
        await conn.run_sync(metadata.create_all)


from functools import wraps
# Middleware-like decorator for metrics + tracing
def instrument_endpoint(endpoint_name: str):
    def decorator(fn):
        @wraps(fn)
        async def wrapper(request: Request, *args, **kwargs):
            method = request.method

            with tracer.start_as_current_span(endpoint_name, kind=SpanKind.SERVER) as span:
                import time
                start = time.time()
                span.set_attribute("http.method", method)
                span.set_attribute("http.route", endpoint_name)
                span_context = trace.get_current_span().get_span_context()
                trace_id = span_context.trace_id or 0
                span_id = span_context.span_id or 0
                trace_flags = getattr(span_context, "trace_flags", 0) or 0

                try:
                    record = LogRecord(
                        timestamp=int(time.time() * 1_000_000_000),  # nanoseconds
                        observed_timestamp=int(time.time() * 1_000_000_000),
                        severity_number=SeverityNumber.INFO,
                        severity_text="INFO",
                        body=f"Endpoint called: {endpoint_name}",
                        attributes={
                            "endpoint": endpoint_name,
                            "method": method,
                        },
                        trace_id=trace_id,
                        span_id=span_id,
                        trace_flags=trace_flags,
                    )
                    logger.emit(record)
                    
                    result = await fn(request=request, *args, **kwargs)
                    status_code = getattr(result, "status_code", 200)
                    span.set_attribute("http.status_code", status_code)
                    return result
                except HTTPException as ex:
                    span.set_attribute("http.status_code", ex.status_code)
                    raise
                finally:
                    duration = time.time() - start
                    REQUEST_COUNT.add(1, {"method": method, "endpoint": endpoint_name})
                    REQUEST_LATENCY.record(
                        duration,
                        {"method": method, "endpoint": endpoint_name},
                    )
                    REQUEST_LATENCY_PROM.labels(method=method, endpoint=endpoint_name).observe(duration)
                    REQUEST_COUNT_PROM.labels(method=method, endpoint=endpoint_name, http_status=str(status_code)).inc()

        return wrapper
    return decorator

@app.post("/api/comment/new", status_code=status.HTTP_201_CREATED, response_model=CommentOut)
@instrument_endpoint("/api/comment/new")
async def create_comment(comment_in: CommentIn, request: Request):
    """Insert a comment into the DB."""
    async with engine.begin() as conn:
        stmt = comments_table.insert().values(
            email=comment_in.email,
            comment=comment_in.comment,
            content_id=comment_in.content_id,
        ).returning(comments_table.c.id)
        result = await conn.execute(stmt)
        new_id = result.scalar_one()
    return {
        "id": new_id,
        "email": comment_in.email,
        "comment": comment_in.comment,
        "content_id": comment_in.content_id,
    }

@app.get("/api/comment/list/{content_id}", response_model=List[CommentOut])
@instrument_endpoint("/api/comment/list/{content_id}")
async def list_comments(content_id: int, request: Request):
    """List comments by content_id"""
    async with engine.connect() as conn:
        stmt = select(comments_table).where(comments_table.c.content_id == content_id).order_by(comments_table.c.id.desc())
        result = await conn.execute(stmt)
        rows = result.fetchall()
        return [
            {"id": r.id, "email": r.email, "comment": r.comment, "content_id": r.content_id} for r in rows
        ]

from starlette.responses import Response

@app.get("/health")
async def health():
    # simple DB check
    try:
        async with engine.connect() as conn:
            await conn.execute(select(1))
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=503, detail=str(e))

@app.get("/metrics")
async def metrics():
# Serve Prometheus metrics in the same process
    data = generate_latest()
    return Response(content=data, media_type=CONTENT_TYPE_LATEST)

# root
@app.get("/")
async def root():
    return {"msg": "Comments API"}