-- Initialize database schema for Kubernetes metrics

-- Create pod_metrics table
CREATE TABLE IF NOT EXISTS pod_metrics (
    id SERIAL PRIMARY KEY,
    pod_name VARCHAR(255) NOT NULL,
    pod_id VARCHAR(255) UNIQUE NOT NULL,
    status VARCHAR(50) NOT NULL,
    node_name VARCHAR(255),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index on pod_id for faster lookups
CREATE INDEX IF NOT EXISTS idx_pod_id ON pod_metrics(pod_id);

-- Create index on timestamp for time-based queries
CREATE INDEX IF NOT EXISTS idx_timestamp ON pod_metrics(timestamp DESC);

-- Create index on pod_name for name-based queries
CREATE INDEX IF NOT EXISTS idx_pod_name ON pod_metrics(pod_name);

-- Create a view for recent pod metrics
CREATE OR REPLACE VIEW recent_pod_metrics AS
SELECT 
    pod_name,
    pod_id,
    status,
    node_name,
    timestamp
FROM pod_metrics
ORDER BY timestamp DESC
LIMIT 100;

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE k8s_metrics TO postgres;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;

