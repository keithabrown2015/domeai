import type { VercelRequest, VercelResponse } from '@vercel/node';

// Helper function to detect if query needs web search for recent/current information
function shouldUseWebSearch(message: string): boolean {
  const m = message.toLowerCase();
  return (
    m.includes("today") ||
    m.includes("yesterday") ||
    m.includes("this week") ||
    m.includes("score") ||
    m.includes("game") ||
    m.includes("stock price") ||
    m.includes("news") ||
    m.includes("weather") ||
    m.includes("what happened") ||
    m.includes("current") ||
    m.includes("latest") ||
    m.includes("recent") ||
    m.includes("now") ||
    m.includes("population") ||
    m.includes("rankings") ||
    m.includes("poll")
  );
}

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

    console.log('🔍 Ray processing query:', query);

    const needsWeb = shouldUseWebSearch(query);
    console.log('🤔 Web search needed:', needsWeb ? 'YES' : 'NO');

    let sources: string[] = [];
    let finalAnswer = '';

    // Use OpenAI Responses API with web_search tool if needed
    if (needsWeb) {
      console.log('🌐 Using OpenAI web search for query:', query);
      
      try {
        // Try OpenAI Responses API first
        const response = await fetch('https://api.openai.com/v1/responses', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${openaiApiKey}`
          },
          body: JSON.stringify({
            model: 'gpt-4o',
            tools: [{ type: 'web_search' }],
            input: [
              {
                role: 'user',
                content: query
              }
            ]
          })
        });

        if (response.ok) {
          const responseData = await response.json();
          const output = responseData.output?.[0]?.content?.[0];
          if (output) {
            finalAnswer = output.type === 'output_text' ? output.text : JSON.stringify(output);
            sources = responseData.sources || [];
            console.log(`✅ OpenAI Responses API completed with ${sources.length} sources`);
          }
        } else {
          throw new Error(`Responses API returned ${response.status}`);
        }
      } catch (error) {
        console.log('⚠️ Responses API not available, using Chat Completions with web search instructions');
        
        // Fallback: Use Chat Completions with web search instructions
        const systemPrompt = `You are Ray, a sharp AI assistant. Answer the user's question using current, up-to-date information from web search.

IMPORTANT: This query requires current/recent information. Use your knowledge of current events, recent news, and up-to-date information to answer. If you have access to web search capabilities, use them to find the most current information.

Answer directly and cite sources when possible.`;

        const chatResponse = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${openaiApiKey}`
          },
          body: JSON.stringify({
            model: 'gpt-4o',
            messages: [
              {
                role: 'system',
                content: systemPrompt
              },
              {
                role: 'user',
                content: query
              }
            ],
            temperature: 0.7,
            max_tokens: 1000
          })
        });

        if (!chatResponse.ok) {
          const errorText = await chatResponse.text();
          throw new Error(`Chat Completions API error: ${chatResponse.status} - ${errorText}`);
        }

        const chatData = await chatResponse.json();
        finalAnswer = chatData.choices?.[0]?.message?.content || '';
        
        // Try to extract URLs from the response
        const urlRegex = /https?:\/\/[^\s]+/g;
        const matches = finalAnswer.match(urlRegex);
        if (matches) {
          sources = matches.slice(0, 5);
        }
        
        console.log('✅ Chat Completions with web search instructions completed');
      }
    } else {
      // No web search needed, use standard Chat Completions
      console.log('📝 No web search needed, using standard Chat Completions');
      
      const systemPrompt = `You are Ray, a sharp AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.

Answer the user's question directly and helpfully.`;

      const chatResponse = await fetch('https://api.openai.com/v1/chat/completions', {
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
              content: systemPrompt
            },
            {
              role: 'user',
              content: query
            }
          ],
          temperature: 0.7,
          max_tokens: 1000
        })
      });

      if (!chatResponse.ok) {
        const errorText = await chatResponse.text();
        throw new Error(`Chat Completions API error: ${chatResponse.status} - ${errorText}`);
      }

      const chatData = await chatResponse.json();
      finalAnswer = chatData.choices?.[0]?.message?.content || '';
      console.log('✅ Standard Chat Completions completed');
    }

    if (!finalAnswer) {
      console.error('❌ No content in final answer response');
      return res.status(500).json({ 
        error: 'Invalid OpenAI response', 
        message: 'No content returned from AI model' 
      });
    }

    console.log('✅ Ray response generated:', finalAnswer.substring(0, 50) + '...');

    // Return response in the format iOS app expects
    return res.status(200).json({
      ok: true,
      relay: 'ray-smart-search',
      prompt: query,
      message: finalAnswer,
      reply: finalAnswer,
      searchPerformed: needsWeb,
      sources: sources
    });

  } catch (error: any) {
    console.error('❌ Internal server error:', error.message);
    return res.status(500).json({ 
      error: 'Internal server error', 
      message: error.message || 'Unknown error occurred'
    });
  }
}
