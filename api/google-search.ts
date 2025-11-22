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

    console.log('🔍 Ray processing query:', query);

    // STEP 1: Ray decides if search is needed
    const searchDecisionResponse = await fetch('https://api.openai.com/v1/chat/completions', {
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
            content: `You are Ray, a sharp AI assistant. Determine if the user's query needs current/real-time information from web search.

Respond ONLY with valid JSON in this exact format:
{"needsSearch": true/false, "searchQuery": "optimized search query"}

Queries NEEDING search:
- Current events, news, recent happenings
- Prices, stock prices, market data
- Population stats, demographics (current year)
- Weather, forecasts
- Recent data, latest information
- "What is happening", "current status"
- Real-time information

Queries NOT needing search:
- General knowledge, explanations
- Calculations, math problems
- Creative tasks, writing
- Historical facts (not recent)
- Definitions, concepts
- Philosophical questions

If needsSearch is true, provide an optimized search query. If false, searchQuery can be empty string.`
          },
          {
            role: 'user',
            content: query
          }
        ],
        temperature: 0.3,
        max_tokens: 200,
        response_format: { type: 'json_object' }
      })
    });

    if (!searchDecisionResponse.ok) {
      const errorText = await searchDecisionResponse.text();
      console.error('❌ OpenAI search decision error:', searchDecisionResponse.status, errorText);
      return res.status(searchDecisionResponse.status).json({ 
        error: 'OpenAI API error', 
        status: searchDecisionResponse.status,
        details: errorText 
      });
    }

    const searchDecisionData = await searchDecisionResponse.json();
    const decisionText = searchDecisionData.choices?.[0]?.message?.content;
    
    if (!decisionText) {
      console.error('❌ No content in search decision response');
      return res.status(500).json({ 
        error: 'Invalid OpenAI response', 
        message: 'No content returned from search decision model' 
      });
    }

    let searchDecision: { needsSearch: boolean; searchQuery: string };
    try {
      searchDecision = JSON.parse(decisionText);
    } catch (e) {
      console.error('❌ Failed to parse search decision JSON:', decisionText);
      // Default to no search if parsing fails
      searchDecision = { needsSearch: false, searchQuery: '' };
    }

    console.log('🤔 Search decision:', searchDecision.needsSearch ? 'YES' : 'NO', searchDecision.searchQuery);

    let searchResults: Array<{ title: string; snippet: string; link: string }> = [];
    let sources: string[] = [];

    // STEP 2: If search is needed, call Google Custom Search API
    if (searchDecision.needsSearch && searchDecision.searchQuery) {
      const googleApiKey = process.env.GOOGLE_API_KEY;
      const googleCx = process.env.GOOGLE_CX;

      if (!googleApiKey || !googleCx) {
        console.error('❌ Google API credentials not found');
        // Continue without search, Ray will answer from knowledge
        console.log('⚠️ Continuing without search due to missing credentials');
      } else {
        console.log('🌐 Calling Google Custom Search API...');
        
        const googleSearchUrl = new URL('https://www.googleapis.com/customsearch/v1');
        googleSearchUrl.searchParams.set('key', googleApiKey);
        googleSearchUrl.searchParams.set('cx', googleCx);
        googleSearchUrl.searchParams.set('q', searchDecision.searchQuery);
        googleSearchUrl.searchParams.set('num', '3');

        const googleResponse = await fetch(googleSearchUrl.toString());

        if (!googleResponse.ok) {
          const errorText = await googleResponse.text();
          console.error('❌ Google Search API error:', googleResponse.status, errorText);
          // Continue without search results
        } else {
          const googleData = await googleResponse.json();
          const items = googleData.items || [];
          
          searchResults = items.slice(0, 3).map((item: any) => ({
            title: item.title || '',
            snippet: item.snippet || '',
            link: item.link || ''
          }));

          sources = searchResults.map(r => r.link);
          console.log(`✅ Found ${searchResults.length} search results`);
        }
      }
    }

    // STEP 3: Generate final answer with or without search results
    const contextPrompt = searchResults.length > 0
      ? `User query: ${query}\n\nSearch results:\n${searchResults.map((r, i) => `${i + 1}. ${r.title}\n   ${r.snippet}\n   ${r.link}`).join('\n\n')}\n\nSynthesize a natural answer using the search results above. Cite sources naturally in your response.`
      : query;

    const finalAnswerResponse = await fetch('https://api.openai.com/v1/chat/completions', {
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
            content: `You are Ray, a sharp, friendly AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.

DOME FILING SYSTEM:

- Projects: User-created containers (examples: School, Home, Car, Church, Recipes, Business)

- Tags: Optional labels that span across projects

- Saved Items: Content with title, text, timestamp, project, and optional tags

SAVING BEHAVIOR:

When user says "save this", "put in Dome", "keep this", or "save under [Project]":

1. Determine the correct Project (ask if unclear)

2. Suggest creating a new Project if none fits

3. Apply tags if mentioned

4. Generate a clear title

5. Confirm the save

RETRIEVAL BEHAVIOR:

Respond to requests like:

- "Show me everything about [topic]"

- "Open my [project] project"

- "What did I save about [X]?"

- "Show everything under [Project]"

TONE:

Be conversational, helpful, and efficient. Answer in 2-3 sentences unless more detail is needed. Use natural language, not robotic responses.

IMPORTANT: You cannot actually save or retrieve yet (the Dome UI is being built), but you should respond AS IF you can, and tell users "I'll save that to your Dome once the filing system is ready."

${searchResults.length > 0 ? 'Use the provided search results to answer the query. Cite sources naturally.' : ''}`
          },
          {
            role: 'user',
            content: contextPrompt
          }
        ],
        temperature: 0.7,
        max_tokens: 1000
      })
    });

    if (!finalAnswerResponse.ok) {
      const errorText = await finalAnswerResponse.text();
      console.error('❌ OpenAI final answer error:', finalAnswerResponse.status, errorText);
      return res.status(finalAnswerResponse.status).json({ 
        error: 'OpenAI API error', 
        status: finalAnswerResponse.status,
        details: errorText 
      });
    }

    const finalAnswerData = await finalAnswerResponse.json();
    const finalAnswer = finalAnswerData.choices?.[0]?.message?.content;

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
      searchPerformed: searchDecision.needsSearch && searchResults.length > 0,
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
