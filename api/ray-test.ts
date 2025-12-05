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
    console.log('❌ Unauthorized request to /api/ray-test');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const testQuery = "What is Mississippi's population?";
    console.log('🧪 ========== STARTING TIER 3 TEST ==========');
    console.log('🧪 Test Query:', testQuery);

    // Check for required environment variables
    const openaiApiKey = process.env.OPENAI_API_KEY;

    if (!openaiApiKey) {
      return res.status(500).json({ error: 'OPENAI_API_KEY not configured' });
    }

    // STEP 1: Use OpenAI Responses API with web_search tool
    console.log('🧪 STEP 1: Calling OpenAI Responses API with web_search tool...');
    let extractedMessage = '';
    let sources: string[] = [];
    let searchPerformed = false;

    try {
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
              content: testQuery
            }
          ]
        })
      });

      if (response.ok) {
        const responseData = await response.json();
        console.log('🧪 STEP 1 RESULT:');
        console.log('🧪   Response structure:', JSON.stringify(responseData, null, 2));
        
        const output = responseData.output?.[0]?.content?.[0];
        if (output) {
          extractedMessage = output.type === 'output_text' ? output.text : JSON.stringify(output);
          sources = responseData.sources || [];
          searchPerformed = true;
          console.log('🧪   Message extracted:', extractedMessage.substring(0, 200));
          console.log('🧪   Sources count:', sources.length);
        }
      } else {
        throw new Error(`Responses API returned ${response.status}`);
      }
    } catch (error: any) {
      console.log('🧪 STEP 1 FALLBACK: Responses API not available, using Chat Completions with web search instructions');
      
      // Fallback: Use Chat Completions with web search instructions
      const systemPrompt = `You are Ray, a smart AI assistant helping the user with current information.

The user asked: ${testQuery}

YOUR JOB: Answer the user's question DIRECTLY using current, up-to-date information. Extract and present concrete data points (numbers, dates, facts, rankings, scores, etc.).

CRITICAL INSTRUCTIONS:

1. EXTRACT SPECIFIC DATA: When answering, extract and present concrete facts directly.

2. PRESENT DATA CLEARLY: When presenting numbers or facts, state them clearly and confidently.

3. USE CURRENT INFORMATION: Use your knowledge of current events and recent data to answer.

Be direct, specific, and helpful. Answer in 2-3 clear sentences with concrete data points.`;

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
              content: testQuery
            }
          ],
          temperature: 0.7,
          max_tokens: 1000
        })
      });

      if (!chatResponse.ok) {
        const errorText = await chatResponse.text();
        console.error('🧪 STEP 1 ERROR:', chatResponse.status, errorText);
        return res.status(500).json({ error: 'OpenAI API error', details: errorText });
      }

      const chatData = await chatResponse.json();
      extractedMessage = chatData.choices?.[0]?.message?.content || '';
      
      // Try to extract URLs from the response
      const urlRegex = /https?:\/\/[^\s]+/g;
      const matches = extractedMessage.match(urlRegex);
      if (matches) {
        sources = matches.slice(0, 5);
      }
      
      console.log('🧪 STEP 1 RESULT (Fallback):');
      console.log('🧪   Message extracted:', extractedMessage.substring(0, 200));
      console.log('🧪   Sources count:', sources.length);
    }

    // STEP 2: Final output
    console.log('🧪 STEP 2: Final output...');
    
    const finalOutput = {
      ok: true,
      tier: 3,
      model: 'openai-web-search',
      message: extractedMessage,
      reasoning: 'Test query requires current data',
      sources: sources,
      testResults: {
        originalQuery: testQuery,
        responseLength: extractedMessage.length,
        searchPerformed: searchPerformed,
        sourcesCount: sources.length,
        containsPopulationData: /\d+[.,]?\d*\s*(million|thousand|billion|people|residents)/i.test(extractedMessage),
        containsMississippi: extractedMessage.includes('Mississippi')
      }
    };

    console.log('🧪 ========== TEST COMPLETE ==========');
    console.log('🧪 Final output:', JSON.stringify(finalOutput, null, 2));

    return res.status(200).json(finalOutput);

  } catch (error: any) {
    console.error('🧪 TEST ERROR:', error.message);
    console.error('🧪 Error stack:', error.stack);
    return res.status(500).json({ 
      error: 'Test failed', 
      message: error.message || 'Unknown error occurred',
      stack: error.stack
    });
  }
}

