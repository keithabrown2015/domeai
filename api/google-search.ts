import type { VercelRequest, VercelResponse } from '@vercel/node';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  try {
    // Parse request body
    const { query, num } = req.body;

    // Validate query parameter
    if (!query || typeof query !== 'string') {
      return res.status(400).json({ 
        error: 'Bad request', 
        message: 'Missing or invalid "query" field in request body' 
      });
    }

    // Check for OpenAI API key
    const openaiApiKey = process.env.OPENAI_API_KEY;
    if (!openaiApiKey) {
      console.error('❌ OPENAI_API_KEY not found in environment variables');
      return res.status(500).json({ 
        error: 'Server configuration error', 
        message: 'OpenAI API key is not configured' 
      });
    }

    console.log('🤖 Ray processing query:', query);

    // Call OpenAI Chat Completions API
    const openaiResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${openaiApiKey}`
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: 'You are Ray, a friendly, sharp assistant living inside DomeAI. Answer clearly and conversationally in a few sentences.'
          },
          {
            role: 'user',
            content: query
          }
        ],
        temperature: 0.7,
        max_tokens: 500
      })
    });

    // Handle OpenAI API errors
    if (!openaiResponse.ok) {
      const errorText = await openaiResponse.text();
      console.error('❌ OpenAI API error:', openaiResponse.status, errorText);
      return res.status(openaiResponse.status).json({ 
        error: 'OpenAI API error', 
        status: openaiResponse.status,
        details: errorText 
      });
    }

    // Parse OpenAI response
    const openaiData = await openaiResponse.json();
    const aiReply = openaiData.choices?.[0]?.message?.content;

    if (!aiReply) {
      console.error('❌ No content in OpenAI response');
      return res.status(500).json({ 
        error: 'Invalid OpenAI response', 
        message: 'No content returned from AI model' 
      });
    }

    console.log('✅ Ray response generated:', aiReply.substring(0, 50) + '...');

    // Return response in the format iOS app expects
    return res.status(200).json({
      ok: true,
      relay: 'ray-openai-chat',
      prompt: query,
      message: aiReply,
      reply: aiReply,
      raw: openaiData // Optional: full OpenAI response for debugging
    });

  } catch (error: any) {
    console.error('❌ Internal server error:', error.message);
    return res.status(500).json({ 
      error: 'Internal server error', 
      message: error.message || 'Unknown error occurred'
    });
  }
}

