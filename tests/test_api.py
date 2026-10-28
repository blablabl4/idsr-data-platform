"""
Testes de API FastAPI via TestClient.
"""

from fastapi.testclient import TestClient
from src.api import app

client = TestClient(app)


def test_api_health():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_api_predict_delay():
    payload = {
        "distancia_km": 450.0,
        "valor_frete": 32.0,
        "peso_kg": 2.5,
        "prazo_estimado_dias": 5.0
    }
    response = client.post("/api/v1/predict-delay", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert "probabilidade_atraso" in data
    assert "nivel_risco" in data


def test_api_rag_query():
    payload = {"pergunta": "Como o dbt trata duplicados na Silver?"}
    response = client.post("/api/v1/rag-query", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert "resposta_ia" in data
    assert len(data["fontes_citadas"]) >= 1


def test_api_lakehouse_metrics():
    response = client.get("/api/v1/lakehouse-metrics")
    assert response.status_code == 200
    data = response.json()
    assert data["pedidos_totais"] > 0
