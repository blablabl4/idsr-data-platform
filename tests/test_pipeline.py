"""
Testes unitários e de integração para o preditor de ML e o motor de RAG.
Executado via: pytest tests/ -v --cov=src
"""

import pytest
from src.ml_predictor import LogisticsDelayPredictor
from src.rag_engine import SemanticKnowledgeBase


def test_predictor_initialization():
    predictor = LogisticsDelayPredictor()
    assert predictor.is_trained is True


def test_predictor_low_risk_scenario():
    predictor = LogisticsDelayPredictor()
    # Distância curta, prazo amplo, frete adequado
    result = predictor.predict_risk(distancia_km=80, valor_frete=18.0, peso_kg=1.0, prazo_estimado_dias=10)
    assert "probabilidade_atraso" in result
    assert result["probabilidade_atraso"] < 35.0
    assert "Baixo" in result["nivel_risco"] or "Moderado" in result["nivel_risco"]


def test_predictor_critical_risk_scenario():
    predictor = LogisticsDelayPredictor()
    # Rota muito longa (2800 km) com prazo irreal de 2 dias
    result = predictor.predict_risk(distancia_km=2800, valor_frete=110.0, peso_kg=25.0, prazo_estimado_dias=2)
    assert result["probabilidade_atraso"] > 60.0
    assert "Crítico" in result["nivel_risco"]


def test_rag_engine_search_relevance():
    rag = SemanticKnowledgeBase()
    results = rag.search("qualidade e testes no dbt", top_k=1)
    assert len(results) == 1
    assert "dbt" in results[0]["conteudo"].lower() or "silver" in results[0]["conteudo"].lower()


def test_rag_grounded_answer():
    rag = SemanticKnowledgeBase()
    answer_payload = rag.generate_grounded_answer("Qual o tempo médio de entrega para o Nordeste?")
    assert "resposta_ia" in answer_payload
    assert len(answer_payload["fontes_citadas"]) > 0
    assert "logistics_sla.md" in answer_payload["fontes_citadas"][0]["arquivo"]
