import express from 'express';
import Anthropic from '@anthropic-ai/sdk';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import { readFileSync, existsSync } from 'fs';
import { HttpsProxyAgent } from 'https-proxy-agent';

// Load .env file if present
const envPath = new URL('.env', import.meta.url).pathname;
if (existsSync(envPath)) {
  readFileSync(envPath, 'utf8').split('\n').forEach(line => {
    const [key, ...vals] = line.split('=');
    if (key && vals.length) process.env[key.trim()] = vals.join('=').trim();
  });
}

// Detect proxy from environment (supports HTTPS_PROXY / https_proxy)
const proxyUrl = process.env.HTTPS_PROXY || process.env.https_proxy ||
                 process.env.HTTP_PROXY  || process.env.http_proxy || null;
const httpAgent = proxyUrl ? new HttpsProxyAgent(proxyUrl) : undefined;

// Resolve auth token: prefer session ingress token file (Bearer auth), fall back to ANTHROPIC_API_KEY
let authToken = null;
const sessionTokenFile = process.env.CLAUDE_SESSION_INGRESS_TOKEN_FILE;
if (sessionTokenFile && existsSync(sessionTokenFile)) {
  authToken = readFileSync(sessionTokenFile, 'utf8').trim();
}

const __dirname = dirname(fileURLToPath(import.meta.url));
const app = express();
const clientOpts = { ...(httpAgent ? { httpAgent } : {}) };
if (authToken) {
  // Use Bearer auth; pass apiKey: null to prevent SDK from reading ANTHROPIC_API_KEY env var
  clientOpts.authToken = authToken;
  clientOpts.apiKey = null;
} else if (!process.env.ANTHROPIC_API_KEY) {
  console.warn('Warning: No API key found. Set ANTHROPIC_API_KEY in .env or ensure CLAUDE_SESSION_INGRESS_TOKEN_FILE is set.');
}
const client = new Anthropic(clientOpts);

app.use(express.json());
app.use(express.static(join(__dirname, 'public')));

// Translate endpoint with streaming
app.post('/api/translate', async (req, res) => {
  const { text, targetLang, sourceLang = 'auto' } = req.body;

  if (!text || !text.trim()) {
    return res.status(400).json({ error: 'Text is required' });
  }
  if (!targetLang) {
    return res.status(400).json({ error: 'Target language is required' });
  }

  const sourceInstruction = sourceLang === 'auto'
    ? 'Detect the source language automatically.'
    : `The source language is ${sourceLang}.`;

  const systemPrompt = `You are a professional translator. Your task is to translate text accurately and naturally.
Rules:
- Translate ONLY the given text. Output the translation directly with no explanations, no preamble, no labels.
- Preserve formatting, line breaks, punctuation, and tone.
- ${sourceInstruction}
- Translate to: ${targetLang}
- If the text is already in ${targetLang}, output it unchanged.`;

  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('Access-Control-Allow-Origin', '*');

  try {
    const stream = client.messages.stream({
      model: 'claude-opus-4-6',
      max_tokens: 4096,
      system: systemPrompt,
      messages: [{ role: 'user', content: text }],
    });

    for await (const event of stream) {
      if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
        res.write(`data: ${JSON.stringify({ text: event.delta.text })}\n\n`);
      }
    }

    const finalMsg = await stream.finalMessage();
    const detectedLang = sourceLang === 'auto' ? await detectLanguage(text, client) : sourceLang;

    res.write(`data: ${JSON.stringify({ done: true, detectedLang })}\n\n`);
    res.end();
  } catch (err) {
    console.error('Translation error:', err);
    res.write(`data: ${JSON.stringify({ error: err.message || 'Translation failed' })}\n\n`);
    res.end();
  }
});

// Language detection endpoint
app.post('/api/detect', async (req, res) => {
  const { text } = req.body;
  if (!text || !text.trim()) {
    return res.json({ language: 'Unknown' });
  }
  try {
    const lang = await detectLanguage(text, client);
    res.json({ language: lang });
  } catch (err) {
    res.json({ language: 'Unknown' });
  }
});

async function detectLanguage(text, client) {
  const response = await client.messages.create({
    model: 'claude-opus-4-6',
    max_tokens: 64,
    messages: [{
      role: 'user',
      content: `Identify the language of this text. Reply with ONLY the language name in English (e.g. "Chinese", "French", "Arabic"). Text: "${text.slice(0, 200)}"`
    }]
  });
  return response.content[0]?.text?.trim() || 'Unknown';
}

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Translation tool running at http://localhost:${PORT}`);
});
