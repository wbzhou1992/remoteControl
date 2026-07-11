const express = require('express');
const cors = require('cors');
const http = require('http');
const { WebSocketServer } = require('ws');
const { v4: uuidv4 } = require('uuid');

const PORT = process.env.PORT || 3000;
const app = express();

app.use(cors());
app.use(express.json());
app.use(express.static(require('path').join(__dirname, '../public')));

/** @type {Map<string, { host: import('ws').WebSocket | null, viewers: Set<import('ws').WebSocket>, createdAt: number }>} */
const rooms = new Map();

/** @type {Map<import('ws').WebSocket, { roomId: string, role: 'host' | 'viewer', clientId: string }>} */
const clients = new Map();

function createRoom() {
  const roomId = uuidv4().slice(0, 8);
  rooms.set(roomId, { host: null, viewers: new Set(), createdAt: Date.now() });
  return roomId;
}

function getRoomInfo(roomId) {
  const room = rooms.get(roomId);
  if (!room) return null;
  return {
    roomId,
    hasHost: room.host !== null,
    viewerCount: room.viewers.size,
    createdAt: room.createdAt,
  };
}

function broadcastToViewers(roomId, message, excludeWs = null) {
  const room = rooms.get(roomId);
  if (!room) return;
  const payload = JSON.stringify(message);
  for (const viewer of room.viewers) {
    if (viewer !== excludeWs && viewer.readyState === 1) {
      viewer.send(payload);
    }
  }
}

function sendToHost(roomId, message) {
  const room = rooms.get(roomId);
  if (!room?.host || room.host.readyState !== 1) return false;
  room.host.send(JSON.stringify(message));
  return true;
}

function cleanupRoom(roomId) {
  const room = rooms.get(roomId);
  if (!room) return;
  if (!room.host && room.viewers.size === 0) {
    rooms.delete(roomId);
  }
}

function handleMessage(ws, raw) {
  let msg;
  try {
    msg = JSON.parse(raw);
  } catch {
    ws.send(JSON.stringify({ type: 'error', message: 'Invalid JSON' }));
    return;
  }

  const client = clients.get(ws);
  if (!client && msg.type !== 'create-room' && msg.type !== 'join-room') {
    ws.send(JSON.stringify({ type: 'error', message: 'Not joined to a room' }));
    return;
  }

  switch (msg.type) {
    case 'create-room': {
      const roomId = createRoom();
      const clientId = uuidv4();
      const room = rooms.get(roomId);
      room.host = ws;
      clients.set(ws, { roomId, role: 'host', clientId });
      ws.send(JSON.stringify({ type: 'room-created', roomId, clientId, role: 'host' }));
      break;
    }

    case 'join-room': {
      const { roomId } = msg;
      const room = rooms.get(roomId);
      if (!room) {
        ws.send(JSON.stringify({ type: 'error', message: 'Room not found' }));
        return;
      }
      if (!room.host) {
        ws.send(JSON.stringify({ type: 'error', message: 'No host in room' }));
        return;
      }
      const clientId = uuidv4();
      room.viewers.add(ws);
      clients.set(ws, { roomId, role: 'viewer', clientId });
      ws.send(JSON.stringify({ type: 'joined', roomId, clientId, role: 'viewer' }));
      if (room.host.readyState === 1) {
        room.host.send(JSON.stringify({ type: 'viewer-joined', clientId }));
      }
      break;
    }

    case 'offer':
    case 'answer':
    case 'ice-candidate': {
      const { targetId, payload } = msg;
      const room = rooms.get(client.roomId);
      if (!room) return;

      const forward = {
        type: msg.type,
        fromId: client.clientId,
        payload,
      };

      if (client.role === 'host') {
        for (const viewer of room.viewers) {
          const viewerClient = clients.get(viewer);
          if (viewerClient?.clientId === targetId) {
            viewer.send(JSON.stringify(forward));
            return;
          }
        }
      } else if (client.role === 'viewer' && room.host) {
        room.host.send(JSON.stringify(forward));
      }
      break;
    }

    case 'input-event': {
      if (client.role !== 'viewer') return;
      sendToHost(client.roomId, {
        type: 'input-event',
        fromId: client.clientId,
        payload: msg.payload,
      });
      break;
    }

    case 'ping':
      ws.send(JSON.stringify({ type: 'pong' }));
      break;

    default:
      ws.send(JSON.stringify({ type: 'error', message: `Unknown type: ${msg.type}` }));
  }
}

function handleDisconnect(ws) {
  const client = clients.get(ws);
  if (!client) return;

  const { roomId, role, clientId } = client;
  const room = rooms.get(roomId);
  clients.delete(ws);

  if (!room) return;

  if (role === 'host') {
    room.host = null;
    broadcastToViewers(roomId, { type: 'host-disconnected' });
    for (const viewer of room.viewers) {
      viewer.close();
      clients.delete(viewer);
    }
    room.viewers.clear();
    rooms.delete(roomId);
  } else {
    room.viewers.delete(ws);
    sendToHost(roomId, { type: 'viewer-left', clientId });
    cleanupRoom(roomId);
  }
}

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', rooms: rooms.size });
});

app.post('/api/rooms', (_req, res) => {
  const roomId = createRoom();
  res.json({ roomId });
});

app.get('/api/rooms/:roomId', (req, res) => {
  const info = getRoomInfo(req.params.roomId);
  if (!info) {
    res.status(404).json({ error: 'Room not found' });
    return;
  }
  res.json(info);
});

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws) => {
  ws.send(JSON.stringify({ type: 'connected', message: 'Signaling server ready' }));

  ws.on('message', (data) => handleMessage(ws, data.toString()));
  ws.on('close', () => handleDisconnect(ws));
  ws.on('error', () => handleDisconnect(ws));
});

setInterval(() => {
  const now = Date.now();
  for (const [roomId, room] of rooms) {
    if (now - room.createdAt > 24 * 60 * 60 * 1000) {
      if (room.host) room.host.close();
      for (const v of room.viewers) v.close();
      rooms.delete(roomId);
    }
  }
}, 60 * 60 * 1000);

server.listen(PORT, () => {
  console.log(`Signaling server running on http://localhost:${PORT}`);
  console.log(`WebSocket endpoint: ws://localhost:${PORT}/ws`);
});
