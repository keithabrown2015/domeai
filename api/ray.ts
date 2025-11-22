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
    console.log('❌ Unauthorized request to /api/ray');
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // Parse request body
    const { query, conversationHistory } = req.body;
    
    // Extract user query
    const userQuery = query || (conversationHistory && Array.isArray(conversationHistory) && conversationHistory.length > 0
      ? conversationHistory[conversationHistory.length - 1]?.content
      : null);

    if (!userQuery || typeof userQuery !== 'string') {
      return res.status(400).json({ 
        error: 'Bad request', 
        message: 'Missing or invalid "query" field in request body' 
      });
    }

    // Use conversationHistory if provided, otherwise create from query
    const messagesArray = conversationHistory && Array.isArray(conversationHistory) && conversationHistory.length > 0
      ? conversationHistory
      : [
          {
            role: 'user',
            content: userQuery
          }
        ];

    // Check for OpenAI API key
    const openaiApiKey = process.env.OPENAI_API_KEY;
    if (!openaiApiKey) {
      console.error('❌ OPENAI_API_KEY not found in environment variables');
      return res.status(500).json({ 
        error: 'Server configuration error', 
        message: 'OpenAI API key is not configured' 
      });
    }

    console.log('🎯 Ray processing query:', userQuery);

    // TIER CLASSIFICATION: Determine which tier to use
    const classificationResponse = await fetch('https://api.openai.com/v1/chat/completions', {
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
            content: `You are Ray's routing system. Analyze the user's query and determine which tier to use.

Respond ONLY with valid JSON in this exact format:
{"tier": 1 | 2 | 3, "reasoning": "brief explanation"}

TIER 1 (gpt-4o-mini): Simple questions, chitchat, basic info, general knowledge, definitions, explanations, casual conversation

TIER 2 (gpt-4o): Complex reasoning, coding help, architecture design, multi-step planning, deep analysis, problem-solving, creative writing, technical explanations

TIER 3 (Google Search + gpt-4o-mini): Current events, news, live data, "today/recent/current/latest", population stats, weather, stocks, sports scores, "is X down", real-time information, recent happenings

Be decisive and choose the most appropriate tier.`
          },
          {
            role: 'user',
            content: userQuery
          }
        ],
        temperature: 0.3,
        max_tokens: 150,
        response_format: { type: 'json_object' }
      })
    });

    if (!classificationResponse.ok) {
      const errorText = await classificationResponse.text();
      console.error('❌ Tier classification error:', classificationResponse.status, errorText);
      return res.status(classificationResponse.status).json({ 
        error: 'OpenAI API error', 
        status: classificationResponse.status,
        details: errorText 
      });
    }

    const classificationData = await classificationResponse.json();
    const classificationText = classificationData.choices?.[0]?.message?.content;
    
    if (!classificationText) {
      console.error('❌ No content in tier classification response');
      return res.status(500).json({ 
        error: 'Invalid OpenAI response', 
        message: 'No content returned from tier classification model' 
      });
    }

    let classification: { tier: number; reasoning: string };
    try {
      classification = JSON.parse(classificationText);
    } catch (e) {
      console.error('❌ Failed to parse tier classification JSON:', classificationText);
      // Default to Tier 1 if parsing fails
      classification = { tier: 1, reasoning: 'Failed to parse classification, defaulting to Tier 1' };
    }

    const tier = classification.tier || 1;
    const reasoning = classification.reasoning || 'No reasoning provided';

    console.log(`🎯 Tier selected: ${tier} - ${reasoning}`);

    let message = '';
    let model = '';
    let sources: string[] = [];

    // TIER 1: Simple queries with gpt-4o-mini
    if (tier === 1) {
      console.log('🤖 Tier 1: Using gpt-4o-mini');
      model = 'gpt-4o-mini';
      

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
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

IMPORTANT: You cannot actually save or retrieve yet (the Dome UI is being built), but you should respond AS IF you can, and tell users "I'll save that to your Dome once the filing system is ready."`
            },
            ...messagesArray
          ],
          temperature: 0.7,
          max_tokens: 1000
        })
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error('❌ Tier 1 OpenAI error:', response.status, errorText);
        throw new Error(`OpenAI API error: ${response.status}`);
      }

      const data = await response.json();
      message = data.choices?.[0]?.message?.content || '';
      
      if (!message) {
        throw new Error('No content returned from OpenAI');
      }

      console.log('✅ Tier 1 response generated');
    }
    // TIER 2: Complex queries with gpt-4o
    else if (tier === 2) {
      console.log('🤖 Tier 2: Using gpt-4o');
      model = 'gpt-4o';
      

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
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
              content: `You are Ray, a sharp, friendly AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.

You excel at complex reasoning, coding, architecture, multi-step planning, and deep analysis. Provide thorough, well-reasoned responses.

DOME FILING SYSTEM:

- Projects: User-created containers (examples: School, Home, Car, Church, Recipes, Business)

- Tags: Optional labels that span across projects

- Saved Items: Content with title, text, timestamp, project, and optional tags

TONE:

Be conversational, helpful, and efficient. Provide detailed, thoughtful answers when needed. Use natural language, not robotic responses.`
            },
            ...messagesArray
          ],
          temperature: 0.7,
          max_tokens: 2000
        })
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error('❌ Tier 2 OpenAI error:', response.status, errorText);
        throw new Error(`OpenAI API error: ${response.status}`);
      }

      const data = await response.json();
      message = data.choices?.[0]?.message?.content || '';
      
      if (!message) {
        throw new Error('No content returned from OpenAI');
      }

      console.log('✅ Tier 2 response generated');
    }
    // TIER 3: Google Search + gpt-4o-mini summary
    else if (tier === 3) {
      console.log('🔍 Tier 3: Using Google Search + gpt-4o-mini');
      model = 'google-search';
      
      const googleApiKey = process.env.GOOGLE_API_KEY;
      const googleCx = process.env.GOOGLE_CX;

      if (!googleApiKey || !googleCx) {
        console.error('❌ Google API credentials not found, falling back to Tier 2');
        // Fallback to Tier 2
        model = 'gpt-4o';
        const messagesArray = messages && Array.isArray(messages) ? messages : [
          {
            role: 'user',
            content: `${userQuery}\n\nNote: I wanted to search for current information, but search is unavailable. Answering from my knowledge instead.`
          }
        ];

        const response = await fetch('https://api.openai.com/v1/chat/completions', {
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
                content: 'You are Ray. Answer the query, noting that you cannot access current/recent information right now.'
              },
              ...messagesArray
            ],
            temperature: 0.7,
            max_tokens: 1000
          })
        });

        if (!response.ok) {
          const errorText = await response.text();
          console.error('❌ Tier 2 fallback error:', response.status, errorText);
          throw new Error(`OpenAI API error: ${response.status}`);
        }

        const data = await response.json();
        message = data.choices?.[0]?.message?.content || '';
        
        if (!message) {
          throw new Error('No content returned from OpenAI');
        }

        console.log('✅ Tier 2 fallback response generated');
      } else {
        // STEP 1: Optimize search query
        console.log('🔍 Optimizing search query...');
        console.log('🔍 Original query:', userQuery);
        
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
                content: `The user asked: ${userQuery}

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

        let optimizedQuery = userQuery; // Fallback to original if optimization fails
        
        if (queryOptimizerResponse.ok) {
          const optimizerData = await queryOptimizerResponse.json();
          const optimizedText = optimizerData.choices?.[0]?.message?.content?.trim();
          
          if (optimizedText) {
            optimizedQuery = optimizedText;
            console.log('✅ Optimized query:', optimizedQuery);
          } else {
            console.log('⚠️ No optimized query returned, using original');
          }
        } else {
          console.log('⚠️ Query optimization failed, using original query');
        }
        
        // STEP 2: Perform Google Search with optimized query
        console.log('🌐 Calling Google Custom Search API...');
        console.log('🔍 Using search query:', optimizedQuery);
        
        const googleSearchUrl = new URL('https://www.googleapis.com/customsearch/v1');
        googleSearchUrl.searchParams.set('key', googleApiKey);
        googleSearchUrl.searchParams.set('cx', googleCx);
        googleSearchUrl.searchParams.set('q', optimizedQuery);
        googleSearchUrl.searchParams.set('num', '3');

        const googleResponse = await fetch(googleSearchUrl.toString());

        if (!googleResponse.ok) {
          const errorText = await googleResponse.text();
          console.error('❌ Google Search API error:', googleResponse.status, errorText);
          // Fallback to Tier 2
          console.log('⚠️ Falling back to Tier 2 due to Google Search error');
          model = 'gpt-4o';
          const messagesArray = messages && Array.isArray(messages) ? messages : [
            {
              role: 'user',
              content: `${userQuery}\n\nNote: Search failed, answering from my knowledge instead.`
            }
          ];

          const fallbackResponse = await fetch('https://api.openai.com/v1/chat/completions', {
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
                  content: 'You are Ray. Answer the query, noting that search is unavailable.'
                },
                ...messagesArray
              ],
              temperature: 0.7,
              max_tokens: 1000
            })
          });

          if (!fallbackResponse.ok) {
            throw new Error(`OpenAI API error: ${fallbackResponse.status}`);
          }

          const fallbackData = await fallbackResponse.json();
          message = fallbackData.choices?.[0]?.message?.content || '';
          
          if (!message) {
            throw new Error('No content returned from OpenAI');
          }
        } else {
          const googleData = await googleResponse.json();
          const items = googleData.items || [];
          
          const searchResults = items.slice(0, 3).map((item: any) => ({
            title: item.title || '',
            snippet: item.snippet || '',
            link: item.link || ''
          }));

          sources = searchResults.map(r => r.link);
          console.log(`✅ Found ${searchResults.length} search results`);

          // Format search results clearly with Source 1, Source 2, etc.
          const formattedResults = searchResults.map((r, i) => 
            `Source ${i + 1}: ${r.title}
Content: ${r.snippet}
URL: ${r.link}`
          ).join('\n\n');

          // Synthesize with gpt-4o (smarter at extracting info)
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
                  content: `You are Ray, a smart AI assistant helping the user with current information.

The user asked: ${userQuery}

I searched Google and found these current sources:

${formattedResults}

Your job: Answer the user's question using these sources.

IMPORTANT: These search result snippets often contain the exact data the user wants (population numbers, rankings, dates, etc.). Look carefully at the snippets and extract the specific information requested.

If you see population numbers, rankings, scores, or other data in the snippets - USE THEM. Don't say "the sources don't contain this" if the data is clearly there in the snippet text.

If the sources truly don't have the answer, admit it and suggest where to look.

Be helpful and confident. Answer in 2-3 clear sentences.`
                }
              ],
              temperature: 0.7,
              max_tokens: 1000
            })
          });

          if (!summaryResponse.ok) {
            const errorText = await summaryResponse.text();
            console.error('❌ Tier 3 summary error:', summaryResponse.status, errorText);
            throw new Error(`OpenAI API error: ${summaryResponse.status}`);
          }

          const summaryData = await summaryResponse.json();
          message = summaryData.choices?.[0]?.message?.content || '';
          
          if (!message) {
            throw new Error('No content returned from OpenAI summary');
          }

          console.log('✅ Tier 3 response generated with search results');
        }
      }
    } else {
      // Invalid tier, default to Tier 1
      console.log('⚠️ Invalid tier, defaulting to Tier 1');
      return res.status(400).json({
        error: 'Invalid tier',
        message: `Tier ${tier} is not valid. Must be 1, 2, or 3.`
      });
    }

    if (!message) {
      throw new Error('No message generated');
    }

    // Return response in the format iOS app expects
    return res.status(200).json({
      ok: true,
      tier: tier,
      model: model,
      message: message,
      reasoning: reasoning,
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

