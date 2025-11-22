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
    console.log('❌ Unauthorized request to /api/vision');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // Read request body
    const { base64Image, prompt, max_tokens } = req.body;

    console.log('👁️ Vision request');

    // Build vision request
    const visionRequest = {
      model: 'gpt-4o',
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            {
              type: 'image_url',
              image_url: { url: `data:image/jpeg;base64,${base64Image}` },
            },
          ],
        },
      ],
      max_tokens: max_tokens || 1000,
    };

    // Forward to OpenAI API
    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify(visionRequest),
    });

    if (!response.ok) {
      const error = await response.text();
      console.error('❌ Vision API error:', response.status, error);
      return res.status(response.status).json({
        error: 'Vision API error',
        details: error,
      });
    }

    const data = await response.json();
    console.log('✅ Vision success');
    return res.status(200).json(data);
  } catch (error: any) {
    console.error('❌ Vision relay error:', error.message);
    return res.status(500).json({
      error: 'Internal server error',
      message: error.message || 'Unknown error occurred',
    });
  }
}

