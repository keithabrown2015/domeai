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
    const googleApiKey = process.env.GOOGLE_API_KEY;
    const googleCx = process.env.GOOGLE_CX;

    if (!openaiApiKey) {
      return res.status(500).json({ error: 'OPENAI_API_KEY not configured' });
    }
    if (!googleApiKey || !googleCx) {
      return res.status(500).json({ error: 'Google API credentials not configured' });
    }

    // STEP 1: Optimize search query
    console.log('🧪 STEP 1: Optimizing search query...');
    const queryOptimizerResponse = await fetch('https://api.openai.com/v1/chat/completions', {
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
            content: `The user asked: ${testQuery}

Generate the best Google search query to find current, accurate information to answer this question.

Rules:
- Remove question words (what, how, when, who)
- Keep only essential keywords
- Add year/month if query is time-sensitive (use 2025, November 2025)
- Make it search-engine friendly
- Maximum 10 words

Respond with ONLY the search query, nothing else.`
          }
        ],
        temperature: 0.3,
        max_tokens: 50
      })
    });

    let optimizedQuery = testQuery;
    if (queryOptimizerResponse.ok) {
      const optimizerData = await queryOptimizerResponse.json();
      const optimizedText = optimizerData.choices?.[0]?.message?.content?.trim();
      if (optimizedText) {
        optimizedQuery = optimizedText;
      }
    }
    console.log('🧪 STEP 1 RESULT:');
    console.log('🧪   Original query:', testQuery);
    console.log('🧪   Optimized query:', optimizedQuery);

    // STEP 2: Call Google Search API
    console.log('🧪 STEP 2: Calling Google Custom Search API...');
    const googleSearchUrl = new URL('https://www.googleapis.com/customsearch/v1');
    googleSearchUrl.searchParams.set('key', googleApiKey);
    googleSearchUrl.searchParams.set('cx', googleCx);
    googleSearchUrl.searchParams.set('q', optimizedQuery);
    googleSearchUrl.searchParams.set('num', '3');

    console.log('🧪   Search URL:', googleSearchUrl.toString());
    const googleResponse = await fetch(googleSearchUrl.toString());

    if (!googleResponse.ok) {
      const errorText = await googleResponse.text();
      console.error('🧪 STEP 2 ERROR:', googleResponse.status, errorText);
      return res.status(500).json({ error: 'Google Search API error', details: errorText });
    }

    const googleData = await googleResponse.json();
    const items = googleData.items || [];
    
    const searchResults = items.slice(0, 3).map((item: any) => ({
      title: item.title || '',
      snippet: item.snippet || '',
      link: item.link || ''
    }));

    console.log('🧪 STEP 2 RESULT:');
    console.log('🧪   Number of results:', searchResults.length);
    console.log('🧪   Results:', JSON.stringify(searchResults, null, 2));

    // STEP 3: Format search results
    console.log('🧪 STEP 3: Formatting search results...');
    const formattedResults = searchResults.map((r, i) => 
      `Source ${i + 1}: ${r.title}
Content: ${r.snippet}
URL: ${r.link}`
    ).join('\n\n');

    console.log('🧪 STEP 3 RESULT:');
    console.log('🧪   Formatted results length:', formattedResults.length);
    console.log('🧪   Formatted results:', formattedResults);

    // STEP 4: Construct prompt
    console.log('🧪 STEP 4: Constructing OpenAI prompt...');
    const systemPrompt = `You are Ray, a smart AI assistant helping the user with current information.

The user asked: ${testQuery}

I searched Google and found these current sources:

${formattedResults}

YOUR JOB: Answer the user's question DIRECTLY using these sources. Extract and present concrete data points (numbers, dates, facts, rankings, scores, etc.) from the search results.

CRITICAL INSTRUCTIONS:

1. EXTRACT SPECIFIC DATA: When the search results contain numbers, rankings, dates, population figures, scores, or any concrete facts - extract them and present them directly in your answer.

2. DO NOT DEFLECT: If the search results contain the requested information, provide it directly. Do NOT say "check the Census Bureau" or "visit the website" when you already have the data in the snippets above.

3. PRESENT DATA CLEARLY: When presenting numbers or facts, state them clearly and confidently. For example:
   - "California's population is approximately 39.2 million" (not "the Census Bureau reports...")
   - "Ohio State is ranked #1 in the AP poll" (not "you can check the AP poll website...")
   - "GitHub is currently operational" (not "check GitHub's status page...")

4. USE THE SNIPPETS: The Content sections above contain the actual data. Read them carefully and extract the specific information the user asked for.

5. ONLY DEFLECT IF TRULY MISSING: Only suggest checking external sources if the search results genuinely don't contain the requested information.

Be direct, specific, and helpful. Answer in 2-3 clear sentences with concrete data points.

MEMORY: You can save information to memory (stored locally on the user's iPhone using Core Data). When users ask you to remember something or save something, confidently save it and confirm the save. When users ask you to retrieve saved information, search your memory and provide it.`;

    console.log('🧪 STEP 4 RESULT:');
    console.log('🧪   System prompt length:', systemPrompt.length);
    console.log('🧪   Prompt contains formatted results?', systemPrompt.includes(formattedResults));
    console.log('🧪   Prompt contains "Source 1"?', systemPrompt.includes('Source 1'));
    console.log('🧪   Prompt contains user query?', systemPrompt.includes(testQuery));
    console.log('🧪   System prompt preview (first 500 chars):', systemPrompt.substring(0, 500));

    // STEP 5: Call OpenAI API
    console.log('🧪 STEP 5: Calling OpenAI API...');
    const summaryResponse = await fetch('https://api.openai.com/v1/chat/completions', {
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
          }
        ],
        temperature: 0.7,
        max_tokens: 1000
      })
    });

    if (!summaryResponse.ok) {
      const errorText = await summaryResponse.text();
      console.error('🧪 STEP 5 ERROR:', summaryResponse.status, errorText);
      return res.status(500).json({ error: 'OpenAI API error', details: errorText });
    }

    const summaryData = await summaryResponse.json();
    console.log('🧪 STEP 5 RESULT:');
    console.log('🧪   OpenAI response status:', summaryResponse.status);
    console.log('🧪   Response structure:', JSON.stringify(summaryData, null, 2));
    console.log('🧪   Number of choices:', summaryData.choices?.length);
    console.log('🧪   Content type:', typeof summaryData.choices?.[0]?.message?.content);
    console.log('🧪   Is content array?', Array.isArray(summaryData.choices?.[0]?.message?.content));
    
    if (Array.isArray(summaryData.choices?.[0]?.message?.content)) {
      console.log('🧪   Content array:', JSON.stringify(summaryData.choices?.[0]?.message?.content, null, 2));
    } else {
      console.log('🧪   Content (first 500 chars):', String(summaryData.choices?.[0]?.message?.content || '').substring(0, 500));
    }

    // STEP 6: Extract response
    console.log('🧪 STEP 6: Extracting response...');
    const rawContent = summaryData.choices?.[0]?.message?.content;
    let extractedMessage = '';

    if (typeof rawContent === 'string') {
      extractedMessage = rawContent;
    } else if (Array.isArray(rawContent)) {
      extractedMessage = rawContent
        .filter((block: any) => block.type === 'text' && block.text)
        .map((block: any) => block.text)
        .join(' ');
    }

    console.log('🧪 STEP 6 RESULT:');
    console.log('🧪   Extracted message length:', extractedMessage.length);
    console.log('🧪   Extracted message (full):', extractedMessage);
    console.log('🧪   Message contains population number?', /\d+[.,]?\d*\s*(million|thousand|billion|people|residents)/i.test(extractedMessage));
    console.log('🧪   Message contains "Mississippi"?', extractedMessage.includes('Mississippi'));
    console.log('🧪   Message contains search result data?', 
      searchResults.some(r => extractedMessage.includes(r.title) || extractedMessage.includes(r.snippet.substring(0, 20))));

    // STEP 7: Final output
    console.log('🧪 STEP 7: Final output...');
    const sources = searchResults.map(r => r.link);
    
    const finalOutput = {
      ok: true,
      tier: 3,
      model: 'google-search',
      message: extractedMessage,
      reasoning: 'Test query requires current data',
      sources: sources,
      testResults: {
        originalQuery: testQuery,
        optimizedQuery: optimizedQuery,
        searchResultsCount: searchResults.length,
        searchResults: searchResults,
        promptLength: systemPrompt.length,
        responseLength: extractedMessage.length,
        containsPopulationData: /\d+[.,]?\d*\s*(million|thousand|billion|people|residents)/i.test(extractedMessage),
        containsMississippi: extractedMessage.includes('Mississippi'),
        containsSearchData: searchResults.some(r => extractedMessage.includes(r.title) || extractedMessage.includes(r.snippet.substring(0, 20)))
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

