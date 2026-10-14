import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App.jsx';
import 'leaflet/dist/leaflet.css';
import './index.css'; 

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);

// to run the project with docker: -Saba
// docker run --rm -p 5173:5173 -v "${PWD}:/app" -w /app node:lts sh -c "npm install && npm run dev -- --host 0.0.0.0 --port 5173"
