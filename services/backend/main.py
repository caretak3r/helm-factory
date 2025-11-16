#!/usr/bin/env python3
"""
Backend service for Kubernetes dashboard.
Acts as middleware between frontend and database, and fetches metrics from Kubernetes API.
"""

import os
import json
import psycopg2
from datetime import datetime
from flask import Flask, jsonify, request
from flask_cors import CORS
from kubernetes import client, config
from kubernetes.client.rest import ApiException

app = Flask(__name__)
CORS(app)

# Database configuration
DB_HOST = os.getenv('DB_HOST', 'database')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME', 'k8s_metrics')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'postgres')

# Kubernetes configuration
NAMESPACE = os.getenv('NAMESPACE', 'platform')

# Initialize Kubernetes client
try:
    config.load_incluster_config()
except config.ConfigException:
    try:
        config.load_kube_config()
    except config.ConfigException:
        print("Warning: Could not load Kubernetes config")

k8s_apps_v1 = client.AppsV1Api()
k8s_core_v1 = client.CoreV1Api()


def get_db_connection():
    """Get database connection."""
    try:
        return psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
    except Exception as e:
        print(f"Database connection error: {e}")
        return None


def store_pod_metrics(pod_name, pod_id, status, node=None):
    """Store pod metrics in database."""
    conn = get_db_connection()
    if not conn:
        return
    
    try:
        cursor = conn.cursor()
        cursor.execute("""
            INSERT INTO pod_metrics (pod_name, pod_id, status, node_name, timestamp)
            VALUES (%s, %s, %s, %s, %s)
            ON CONFLICT (pod_id) 
            DO UPDATE SET 
                pod_name = EXCLUDED.pod_name,
                status = EXCLUDED.status,
                node_name = EXCLUDED.node_name,
                timestamp = EXCLUDED.timestamp
        """, (pod_name, pod_id, status, node, datetime.utcnow()))
        conn.commit()
        cursor.close()
    except Exception as e:
        print(f"Error storing pod metrics: {e}")
    finally:
        conn.close()


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint."""
    return jsonify({'status': 'healthy'}), 200


@app.route('/ready', methods=['GET'])
def ready():
    """Readiness check endpoint."""
    # Check database connection
    conn = get_db_connection()
    if conn:
        conn.close()
        return jsonify({'status': 'ready'}), 200
    return jsonify({'status': 'not ready'}), 503


@app.route('/api/stats', methods=['GET'])
def get_stats():
    """Get overall statistics."""
    try:
        # Get deployments
        deployments = k8s_apps_v1.list_namespaced_deployment(namespace=NAMESPACE)
        total_deployments = len(deployments.items)
        
        # Get pods
        pods = k8s_core_v1.list_namespaced_pod(namespace=NAMESPACE)
        total_pods = len(pods.items)
        running_pods = sum(1 for p in pods.items if p.status.phase == 'Running')
        pending_pods = sum(1 for p in pods.items if p.status.phase == 'Pending')
        
        return jsonify({
            'namespace': NAMESPACE,
            'totalDeployments': total_deployments,
            'totalPods': total_pods,
            'runningPods': running_pods,
            'pendingPods': pending_pods
        }), 200
    except ApiException as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/deployments', methods=['GET'])
def get_deployments():
    """Get list of deployments."""
    try:
        deployments = k8s_apps_v1.list_namespaced_deployment(namespace=NAMESPACE)
        
        result = []
        for dep in deployments.items:
            replicas = dep.spec.replicas or 0
            ready = dep.status.ready_replicas or 0
            available = dep.status.available_replicas or 0
            
            # Calculate age
            age = "N/A"
            if dep.metadata.creation_timestamp:
                delta = datetime.utcnow() - dep.metadata.creation_timestamp.replace(tzinfo=None)
                age = f"{delta.days}d {delta.seconds // 3600}h"
            
            result.append({
                'name': dep.metadata.name,
                'replicas': replicas,
                'ready': ready,
                'available': available,
                'age': age
            })
        
        return jsonify(result), 200
    except ApiException as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/pods', methods=['GET'])
def get_pods():
    """Get list of pods."""
    try:
        pods = k8s_core_v1.list_namespaced_pod(namespace=NAMESPACE)
        
        result = []
        for pod in pods.items:
            pod_id = pod.metadata.uid
            pod_name = pod.metadata.name
            status = pod.status.phase or 'Unknown'
            node = pod.spec.node_name or 'N/A'
            
            # Store in database
            store_pod_metrics(pod_name, pod_id, status, node)
            
            # Calculate age
            age = "N/A"
            if pod.metadata.creation_timestamp:
                delta = datetime.utcnow() - pod.metadata.creation_timestamp.replace(tzinfo=None)
                if delta.days > 0:
                    age = f"{delta.days}d"
                elif delta.seconds > 3600:
                    age = f"{delta.seconds // 3600}h"
                else:
                    age = f"{delta.seconds // 60}m"
            
            result.append({
                'name': pod_name,
                'podId': pod_id,
                'status': status,
                'node': node,
                'age': age
            })
        
        return jsonify(result), 200
    except ApiException as e:
        return jsonify({'error': str(e)}), 500


@app.route('/api/pods/history', methods=['GET'])
def get_pod_history():
    """Get pod metrics history from database."""
    conn = get_db_connection()
    if not conn:
        return jsonify({'error': 'Database not available'}), 503
    
    try:
        cursor = conn.cursor()
        cursor.execute("""
            SELECT pod_name, pod_id, status, node_name, timestamp
            FROM pod_metrics
            ORDER BY timestamp DESC
            LIMIT 100
        """)
        
        results = []
        for row in cursor.fetchall():
            results.append({
                'pod_name': row[0],
                'pod_id': row[1],
                'status': row[2],
                'node': row[3],
                'timestamp': row[4].isoformat() if row[4] else None
            })
        
        cursor.close()
        return jsonify(results), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        conn.close()


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)

