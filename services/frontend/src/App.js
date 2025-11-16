import React, { useState, useEffect } from 'react';
import axios from 'axios';
import './index.css';

const API_URL = process.env.REACT_APP_API_URL || 'http://backend:80';

function App() {
  const [stats, setStats] = useState(null);
  const [deployments, setDeployments] = useState([]);
  const [pods, setPods] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastUpdate, setLastUpdate] = useState(null);

  const fetchData = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const [statsRes, deploymentsRes, podsRes] = await Promise.all([
        axios.get(`${API_URL}/api/stats`),
        axios.get(`${API_URL}/api/deployments`),
        axios.get(`${API_URL}/api/pods`)
      ]);

      setStats(statsRes.data);
      setDeployments(deploymentsRes.data || []);
      setPods(podsRes.data || []);
      setLastUpdate(new Date());
    } catch (err) {
      console.error('Error fetching data:', err);
      setError(err.message || 'Failed to fetch data');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchData();
    const interval = setInterval(fetchData, 30000); // Refresh every 30 seconds
    return () => clearInterval(interval);
  }, []);

  if (loading && !stats) {
    return <div className="loading">Loading Kubernetes dashboard...</div>;
  }

  return (
    <div className="container">
      <div className="header">
        <h1>Kubernetes Dashboard</h1>
        <p>Platform: {stats?.namespace || 'platform'}</p>
        {lastUpdate && (
          <p style={{ fontSize: '14px', opacity: 0.8 }}>
            Last updated: {lastUpdate.toLocaleTimeString()}
          </p>
        )}
        <button className="refresh-btn" onClick={fetchData}>
          Refresh
        </button>
      </div>

      {error && (
        <div className="error">
          Error: {error}
        </div>
      )}

      {stats && (
        <div className="stats-grid">
          <div className="stat-card">
            <h3>Total Deployments</h3>
            <div className="value">{stats.totalDeployments || 0}</div>
          </div>
          <div className="stat-card">
            <h3>Total Pods</h3>
            <div className="value">{stats.totalPods || 0}</div>
          </div>
          <div className="stat-card">
            <h3>Running Pods</h3>
            <div className="value">{stats.runningPods || 0}</div>
          </div>
          <div className="stat-card">
            <h3>Pending Pods</h3>
            <div className="value">{stats.pendingPods || 0}</div>
          </div>
        </div>
      )}

      <div className="table-container">
        <h2>Deployments</h2>
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Replicas</th>
              <th>Ready</th>
              <th>Available</th>
              <th>Age</th>
            </tr>
          </thead>
          <tbody>
            {deployments.length === 0 ? (
              <tr>
                <td colSpan="5" style={{ textAlign: 'center', padding: '20px' }}>
                  No deployments found
                </td>
              </tr>
            ) : (
              deployments.map((deployment) => (
                <tr key={deployment.name}>
                  <td>{deployment.name}</td>
                  <td>{deployment.replicas}</td>
                  <td>{deployment.ready}</td>
                  <td>{deployment.available}</td>
                  <td>{deployment.age}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <div className="table-container">
        <h2>Pods</h2>
        <table>
          <thead>
            <tr>
              <th>Name</th>
              <th>Status</th>
              <th>Node</th>
              <th>Age</th>
              <th>Pod ID</th>
            </tr>
          </thead>
          <tbody>
            {pods.length === 0 ? (
              <tr>
                <td colSpan="5" style={{ textAlign: 'center', padding: '20px' }}>
                  No pods found
                </td>
              </tr>
            ) : (
              pods.map((pod) => (
                <tr key={pod.name}>
                  <td>{pod.name}</td>
                  <td>
                    <span className={`status-badge status-${pod.status.toLowerCase()}`}>
                      {pod.status}
                    </span>
                  </td>
                  <td>{pod.node || 'N/A'}</td>
                  <td>{pod.age}</td>
                  <td style={{ fontFamily: 'monospace', fontSize: '12px' }}>
                    {pod.podId || 'N/A'}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export default App;

