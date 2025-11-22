import type { VercelRequest, VercelResponse } from '@vercel/node';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Only accept POST requests
  if (req.method !== 'POST') {
    return res.status(405).json({ 
      error: 'Method not allowed', 
      message: 'Only POST requests are accepted' 
    });
  }

  // Check x-app-token header
  const appToken = req.headers['x-app-token'];
  if (appToken !== process.env.APP_TOKEN) {
    console.log('❌ Unauthorized request to /api/openai');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // Read request body
    const { messages, model, max_tokens, temperature } = req.body;

    console.log('🤖 OpenAI relay:', {
      messageCount: messages?.length,
      model: model || 'gpt-4o-mini',
    });

    // Forward to OpenAI API
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: model || 'gpt-4o-mini',
        messages,
        max_tokens: max_tokens || 1000,
        temperature: temperature || 0.7,
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      console.error('❌ OpenAI API error:', response.status, error);
      return res.status(response.status).json({
        error: 'OpenAI API error',
        details: error,
      });
    }

    const data = await response.json();
    console.log('RAW OPENAI RESPONSE:', JSON.stringify(data, null, 2));
    console.log('✅ OpenAI success');
    return res.status(200).json(data);
  } catch (error: any) {
    console.error('❌ Relay error:', error.message);
    return res.status(500).json({
      error: 'Internal server error',
      message: error.message || 'Unknown error occurred',
    });
  }
}
