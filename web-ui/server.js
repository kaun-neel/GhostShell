const express = require('express');
const { WebSocketServer } = require('ws');
const { spawn } = require('child_process');
const path = require('path');
const http = require('http');

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'index.html'));
});

wss.on('connection', (ws) => {
  const shell = spawn('stack', ['exec', 'my-shell'], {
    cwd: path.join(__dirname, '..'),
    env: process.env,
    shell: true
  });

  const banner =
  `\r\n\x1b[1;35m` +
  `  ██████╗ ██╗  ██╗ ██████╗ ███████╗████████╗███████╗██╗  ██╗███████╗██╗     ██╗\r\n` +
  ` ██╔════╝ ██║  ██║██╔═══██╗██╔════╝╚══██╔══╝██╔════╝██║  ██║██╔════╝██║     ██║\r\n` +
  ` ██║  ███╗███████║██║   ██║███████╗   ██║   ███████╗███████║█████╗  ██║     ██║\r\n` +
  ` ██║   ██║██╔══██║██║   ██║╚════██║   ██║   ╚════██║██╔══██║██╔══╝  ██║     ██║\r\n` +
  ` ╚██████╔╝██║  ██║╚██████╔╝███████║   ██║   ███████║██║  ██║███████╗███████╗███████╗\r\n` +
  `  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝╚══════╝╚══════╝\r\n` +
  `\x1b[0m` +
  `\x1b[90m ──────────────────────────────────────────────────────────────────────────────\x1b[0m\r\n` +
  `\x1b[1;37m  Built by \x1b[1;32mIndraneel Bose\x1b[0m` +
  `\x1b[90m  │  \x1b[0m\x1b[1;34m github.com/kaun-neel\x1b[0m\r\n` +
  `\x1b[90m  IIT Patna · B.Sc. Computer Science & Data Analytics\x1b[0m\r\n` +
  `\x1b[90m ──────────────────────────────────────────────────────────────────────────────\x1b[0m\r\n` +
  `\x1b[33m  Builtins: \x1b[0mecho  exit  type  pwd  cd\r\n` +
  `\x1b[33m  Features: \x1b[0mTab completion · I/O Redirection · Quote parsing\r\n` +
  `\x1b[90m ──────────────────────────────────────────────────────────────────────────────\x1b[0m\r\n\r\n`;

  ws.send(JSON.stringify({ type: 'output', data: banner }));

  shell.stdout.on('data', (data) => {
    ws.send(JSON.stringify({ type: 'output', data: data.toString() }));
  });

  shell.stderr.on('data', (data) => {
    ws.send(JSON.stringify({ type: 'output', data: data.toString() }));
  });

  shell.on('close', (code) => {
    ws.send(JSON.stringify({ type: 'exit', code }));
    ws.close();
  });

  ws.on('message', (msg) => {
    const { data } = JSON.parse(msg);
    shell.stdin.write(data);
  });

  ws.on('close', () => {
    shell.kill();
  });
});

server.listen(3000, () => {
  console.log('GhostShell running at http://localhost:3000');
});