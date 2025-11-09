export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const appToken = req.headers['x-app-token'];
  if (appToken !== process.env.APP_TOKEN) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const { messages, model, max_tokens, temperature } = req.body;

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
      console.error('OpenAI API Error:', error);
      return res.status(response.status).json({ error: 'OpenAI API error' });
    }

    const data = await response.json();
    return res.status(200).json(data);
  } catch (error) {
    console.error('Relay error:', error);
    return res.status(500).json({ error: 'Internal server error' });
  }
}

