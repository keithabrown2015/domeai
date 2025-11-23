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

  // Helper function to extract content from OpenAI response
  const extractContent = (responseData: any): string => {
    const choice = responseData.choices?.[0];
    if (!choice) {
      console.error('❌ No choices found in OpenAI response');
      return '';
    }

    const messageContent = choice.message?.content;
    if (!messageContent) {
      console.error('❌ No content found in OpenAI response message');
      return '';
    }

    // Handle string content
    if (typeof messageContent === 'string') {
      return messageContent;
    }

    // Handle array content (multimodal responses)
    if (Array.isArray(messageContent)) {
      const textBlocks = messageContent
        .filter((block: any) => block.type === 'text' && block.text)
        .map((block: any) => block.text)
        .join(' ');
      
      if (textBlocks) {
        return textBlocks;
      }
      
      // Fallback: try to extract any string values
      const allText = messageContent
        .map((block: any) => {
          if (typeof block === 'string') return block;
          if (block.text) return block.text;
          if (block.content) return block.content;
          return '';
        })
        .filter(Boolean)
        .join(' ');
      
      return allText;
    }

    console.error('❌ Unknown content format:', typeof messageContent);
    return '';
  };

  try {
    // CRITICAL: Log what we received from iOS app
    console.log('📥 RECEIVED conversationHistory:', JSON.stringify(req.body.conversationHistory || [], null, 2));
    console.log('📥 RECEIVED query:', req.body.query);
    console.log('📥 RECEIVED full body:', JSON.stringify(req.body, null, 2));
    
    // Parse request body
    const { query, conversationHistory } = req.body;

    if (!query || typeof query !== 'string') {
      return res.status(400).json({ 
        error: 'Bad request', 
        message: 'Missing or invalid "query" field in request body' 
      });
    }

    const userQuery = query;
    console.log('📥 Request received - Query:', userQuery.substring(0, 100));

    // Use conversation history from request body (sent from frontend)
    let messagesArray: any[] = [];
    
    // DEBUG: Log received conversation history
    console.log('🔍 DEBUG: Received conversationHistory:', JSON.stringify(conversationHistory, null, 2));
    console.log('🔍 DEBUG: conversationHistory type:', typeof conversationHistory);
    console.log('🔍 DEBUG: conversationHistory is array?', Array.isArray(conversationHistory));
    console.log('🔍 DEBUG: conversationHistory length:', conversationHistory && Array.isArray(conversationHistory) ? conversationHistory.length : 0);
    
    if (conversationHistory && Array.isArray(conversationHistory) && conversationHistory.length > 0) {
      messagesArray = [...conversationHistory];
      console.log('📝 Received', messagesArray.length, 'messages in conversation history');
      console.log('📝 Conversation history preview:', JSON.stringify(messagesArray.slice(0, 3), null, 2));
    } else {
      console.log('📝 No conversation history provided, starting new conversation');
      // Fallback: create array with just current query
      messagesArray = [{
        role: 'user',
        content: userQuery
      }];
    }

    // Add current user message if not already included
    const lastMessage = messagesArray[messagesArray.length - 1];
    const currentQueryInHistory = lastMessage && 
      lastMessage.role === 'user' && 
      lastMessage.content === userQuery;
    
    if (!currentQueryInHistory) {
      messagesArray.push({
        role: 'user',
        content: userQuery
      });
      console.log('📝 Added current user message. Total messages:', messagesArray.length);
    } else {
      console.log('📝 Current query already in conversation history');
    }

    // CRITICAL: Verify messagesArray has conversation history
    console.log('🔍 DEBUG: Final messagesArray length:', messagesArray.length);
    console.log('🔍 DEBUG: Final messagesArray:', JSON.stringify(messagesArray, null, 2));

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

TIER 3 (Google Search + gpt-4o): Current events, news, live data, "today/recent/current/latest", population stats, weather, stocks, sports scores, "is X down", real-time information, recent happenings

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
    const classificationText = extractContent(classificationData);
    
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

    // Initialize response variables
    const requestId = Date.now().toString() + '-' + Math.random().toString(36).substring(7);
    console.log('🎯 Request ID:', requestId);
    
    let message = '';
    let model = '';
    let sources: string[] = [];
    
    // TIER 1: Simple queries with gpt-4o-mini
    if (tier === 1) {
      console.log('🤖 Tier 1: Using gpt-4o-mini');
      sources = [];
      model = 'gpt-4o-mini';
      
      const tier1Messages = [
        {
          role: 'system',
          content: `You are Ray, a sharp, friendly AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.

Be conversational, helpful, and efficient. Answer in 2-3 sentences unless more detail is needed. Use natural language, not robotic responses.

You have access to the full conversation history below. Use it to maintain context and answer questions that reference previous messages.`
        },
        ...messagesArray  // Full conversation history from frontend
      ];

      console.log('🤖 Tier 1 - Sending', tier1Messages.length, 'messages to OpenAI');
      // CRITICAL: Verify conversation history is included
      console.log('🔍 DEBUG: Tier 1 messagesArray length:', messagesArray.length);
      console.log('🔍 DEBUG: Tier 1 messagesArray:', JSON.stringify(messagesArray, null, 2));
      console.log('🔍 DEBUG: Tier 1 tier1Messages length:', tier1Messages.length);
      // DEBUG: Log messages array being sent to OpenAI
      console.log('🔍 DEBUG: Sending to OpenAI messages array:', JSON.stringify(tier1Messages, null, 2));
      console.log('🔍 DEBUG: Messages being sent to OpenAI:', JSON.stringify(tier1Messages, null, 2));
      
      // CRITICAL: Log exactly what's being sent to OpenAI
      console.log('🚀 SENDING TO OPENAI - Messages array:', JSON.stringify(tier1Messages, null, 2));
      console.log('🚀 Number of messages:', tier1Messages?.length || 0);

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${openaiApiKey}`
        },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          messages: tier1Messages,  // This includes system prompt + full conversation history
          temperature: 0.7,
          max_tokens: 1000
        })
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error('❌ Tier 1 OpenAI error:', response.status, errorText);
        throw new Error(`OpenAI API error: ${response.status}`);
      }

      const responseData = await response.json();
      message = extractContent(responseData);
      console.log('✅ Tier 1 response generated');
      console.log('🔍 DEBUG: OpenAI response received');
    }
    // TIER 2: Complex queries with gpt-4o
    else if (tier === 2) {
      console.log('🤖 Tier 2: Using gpt-4o');
      sources = [];
      model = 'gpt-4o';
      
      const tier2Messages = [
        {
          role: 'system',
          content: `You are Ray, a sharp, friendly AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.

You excel at complex reasoning, coding, architecture, multi-step planning, and deep analysis. Provide thorough, well-reasoned responses.

Be conversational, helpful, and efficient. Provide detailed, thoughtful answers when needed. Use natural language, not robotic responses.

You have access to the full conversation history below. Use it to maintain context and answer questions that reference previous messages.`
        },
        ...messagesArray  // Full conversation history from frontend
      ];

      console.log('🤖 Tier 2 - Sending', tier2Messages.length, 'messages to OpenAI');
      // CRITICAL: Verify conversation history is included
      console.log('🔍 DEBUG: Tier 2 messagesArray length:', messagesArray.length);
      console.log('🔍 DEBUG: Tier 2 messagesArray:', JSON.stringify(messagesArray, null, 2));
      console.log('🔍 DEBUG: Tier 2 tier2Messages length:', tier2Messages.length);
      // DEBUG: Log messages array being sent to OpenAI
      console.log('🔍 DEBUG: Sending to OpenAI messages array:', JSON.stringify(tier2Messages, null, 2));
      console.log('🔍 DEBUG: Messages being sent to OpenAI:', JSON.stringify(tier2Messages, null, 2));
      
      // CRITICAL: Log exactly what's being sent to OpenAI
      console.log('🚀 SENDING TO OPENAI - Messages array:', JSON.stringify(tier2Messages, null, 2));
      console.log('🚀 Number of messages:', tier2Messages?.length || 0);

      const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${openaiApiKey}`
        },
        body: JSON.stringify({
          model: 'gpt-4o',
          messages: tier2Messages,
          temperature: 0.7,
          max_tokens: 2000
        })
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error('❌ Tier 2 OpenAI error:', response.status, errorText);
        throw new Error(`OpenAI API error: ${response.status}`);
      }

      const responseData = await response.json();
      message = extractContent(responseData);
      console.log('✅ Tier 2 response generated');
      console.log('🔍 DEBUG: OpenAI response received');
    }
    // TIER 3: Google Search + gpt-4o summary
    else if (tier === 3) {
      console.log('🔍 Tier 3: Using Google Search + gpt-4o');
      model = 'google-search';
      
      const googleApiKey = process.env.GOOGLE_API_KEY;
      const googleCx = process.env.GOOGLE_CX;
      
      if (!googleApiKey || !googleCx) {
        console.error('❌ Google API credentials not found, falling back to Tier 2');
        sources = [];
        // Fallback to Tier 2
        model = 'gpt-4o';
        const fallbackMessagesArray = messagesArray.length > 0 ? messagesArray : [
          {
            role: 'user',
            content: `${userQuery}\n\nNote: I wanted to search for current information, but search is unavailable. Answering from my knowledge instead.`
          }
        ];

        const fallbackTier2Messages = [
          {
            role: 'system',
            content: `You are Ray. Answer the query, noting that you cannot access current/recent information right now.`
          },
          ...fallbackMessagesArray
        ];

        // CRITICAL: Verify conversation history is included in fallback
        console.log('🔍 DEBUG: Tier 3 fallback messagesArray length:', messagesArray.length);
        console.log('🔍 DEBUG: Tier 3 fallback messagesArray:', JSON.stringify(messagesArray, null, 2));
        console.log('🔍 DEBUG: Tier 3 fallback fallbackTier2Messages length:', fallbackTier2Messages.length);
        // DEBUG: Log messages array being sent to OpenAI (fallback)
        console.log('🔍 DEBUG: Sending to OpenAI messages array (Tier 3 fallback):', JSON.stringify(fallbackTier2Messages, null, 2));
        console.log('🔍 DEBUG: Messages being sent to OpenAI:', JSON.stringify(fallbackTier2Messages, null, 2));
        
        // CRITICAL: Log exactly what's being sent to OpenAI
        console.log('🚀 SENDING TO OPENAI - Messages array:', JSON.stringify(fallbackTier2Messages, null, 2));
        console.log('🚀 Number of messages:', fallbackTier2Messages?.length || 0);

        const response = await fetch('https://api.openai.com/v1/chat/completions', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${openaiApiKey}`
          },
          body: JSON.stringify({
            model: 'gpt-4o',
            messages: fallbackTier2Messages,
            temperature: 0.7,
            max_tokens: 2000
          })
        });

        if (!response.ok) {
          const errorText = await response.text();
          console.error('❌ Tier 2 fallback error:', response.status, errorText);
          throw new Error(`OpenAI API error: ${response.status}`);
        }

        const responseData = await response.json();
        message = extractContent(responseData);
        console.log('✅ Tier 2 fallback response generated');
        console.log('🔍 DEBUG: OpenAI response received');
      } else {
        // STEP 1: Optimize search query
        console.log('🔍 Optimizing search query...');
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

        if (!queryOptimizerResponse.ok) {
          console.error('❌ Query optimizer error, using original query');
        }

        const optimizerData = await queryOptimizerResponse.json();
        const optimizedQuery = extractContent(optimizerData).trim() || userQuery;
        console.log('🔍 Original query:', userQuery);
        console.log('🔍 Optimized query:', optimizedQuery);

        // STEP 2: Google Custom Search
        console.log('🔍 Calling Google Custom Search API...');
        const searchUrl = `https://www.googleapis.com/customsearch/v1?key=${googleApiKey}&cx=${googleCx}&q=${encodeURIComponent(optimizedQuery)}`;
        
        let searchResults: any[] = [];
        try {
          const searchResponse = await fetch(searchUrl);
          if (searchResponse.ok) {
            const searchData = await searchResponse.json();
            searchResults = (searchData.items || []).slice(0, 3);
            console.log('🔍 Search results:', searchResults.length);
            
            // Extract sources
            sources = searchResults.map((r: any) => r.link).filter(Boolean);
          } else {
            console.error('❌ Google Search API error:', searchResponse.status);
          }
        } catch (searchError) {
          console.error('❌ Google Search error:', searchError);
        }

        if (searchResults.length === 0) {
          console.log('⚠️ No search results, falling back to Tier 2');
          sources = [];
          model = 'gpt-4o';
          const fallbackMessagesArray = messagesArray.length > 0 ? messagesArray : [
            {
              role: 'user',
              content: `${userQuery}\n\nNote: Search failed, answering from my knowledge instead.`
            }
          ];

          const fallbackTier2MessagesNoSearch = [
            {
              role: 'system',
              content: `You are Ray. Answer the query, noting that search is unavailable.`
            },
            ...fallbackMessagesArray
          ];

          // CRITICAL: Verify conversation history is included in fallback (no search)
          console.log('🔍 DEBUG: Tier 3 fallback (no search) messagesArray length:', messagesArray.length);
          console.log('🔍 DEBUG: Tier 3 fallback (no search) messagesArray:', JSON.stringify(messagesArray, null, 2));
          console.log('🔍 DEBUG: Tier 3 fallback (no search) fallbackTier2MessagesNoSearch length:', fallbackTier2MessagesNoSearch.length);
          // DEBUG: Log messages array being sent to OpenAI (fallback - no search results)
          console.log('🔍 DEBUG: Sending to OpenAI messages array (Tier 3 fallback - no search):', JSON.stringify(fallbackTier2MessagesNoSearch, null, 2));
          console.log('🔍 DEBUG: Messages being sent to OpenAI:', JSON.stringify(fallbackTier2MessagesNoSearch, null, 2));
          
          // CRITICAL: Log exactly what's being sent to OpenAI
          console.log('🚀 SENDING TO OPENAI - Messages array:', JSON.stringify(fallbackTier2MessagesNoSearch, null, 2));
          console.log('🚀 Number of messages:', fallbackTier2MessagesNoSearch?.length || 0);

          const fallbackResponse = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${openaiApiKey}`
            },
            body: JSON.stringify({
              model: 'gpt-4o',
              messages: fallbackTier2MessagesNoSearch,  // This includes system prompt + full conversation history
              temperature: 0.7,
              max_tokens: 2000
            })
          });

          if (!fallbackResponse.ok) {
            const errorText = await fallbackResponse.text();
            console.error('❌ Tier 3 fallback error:', fallbackResponse.status, errorText);
            throw new Error(`OpenAI API error: ${fallbackResponse.status}`);
          }

          const fallbackData = await fallbackResponse.json();
          message = extractContent(fallbackData);
          console.log('✅ Tier 3 fallback response generated');
          console.log('🔍 DEBUG: OpenAI response received');
        } else {
          // STEP 3: Synthesize with gpt-4o
          const formattedResults = searchResults.map((r, i) => 
            `Source ${i + 1}: ${r.title}
Content: ${r.snippet}
URL: ${r.link}`
          ).join('\n\n');

          const systemPrompt = `You are Ray, a smart AI assistant helping the user with current information.

The user asked: ${userQuery}

I searched Google and found these current sources:

${formattedResults}

YOUR JOB: Answer the user's question directly using the information from these sources. Extract and present concrete data points (numbers, dates, facts, rankings, scores, etc.) from the search results.

Be direct, specific, and helpful. Answer in 2-3 clear sentences with concrete data points.

You have access to the full conversation history below. Use it to maintain context.`;

          const tier3Messages = [
            {
              role: 'system',
              content: systemPrompt
            },
            ...messagesArray  // Full conversation history from frontend
          ];

          console.log('🔍 Tier 3 - Sending', tier3Messages.length, 'messages to OpenAI for synthesis');
          // CRITICAL: Verify conversation history is included
          console.log('🔍 DEBUG: Tier 3 messagesArray length:', messagesArray.length);
          console.log('🔍 DEBUG: Tier 3 messagesArray:', JSON.stringify(messagesArray, null, 2));
          console.log('🔍 DEBUG: Tier 3 tier3Messages length:', tier3Messages.length);
          // DEBUG: Log messages array being sent to OpenAI
          console.log('🔍 DEBUG: Sending to OpenAI messages array:', JSON.stringify(tier3Messages, null, 2));
          console.log('🔍 DEBUG: Messages being sent to OpenAI:', JSON.stringify(tier3Messages, null, 2));
          
          // CRITICAL: Log exactly what's being sent to OpenAI
          console.log('🚀 SENDING TO OPENAI - Messages array:', JSON.stringify(tier3Messages, null, 2));
          console.log('🚀 Number of messages:', tier3Messages?.length || 0);

          const summaryResponse = await fetch('https://api.openai.com/v1/chat/completions', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${openaiApiKey}`
            },
            body: JSON.stringify({
              model: 'gpt-4o',
              messages: tier3Messages,
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
          message = extractContent(summaryData);
          console.log('✅ Tier 3 response generated with search results');
          console.log('🔍 DEBUG: OpenAI response received');
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

    // Return response
    // Note: Frontend manages conversation history - we don't need to save it here
    return res.status(200).json({
      ok: true,
      tier: tier,
      model: model,
      message: message,
      reasoning: reasoning,
      sources: sources
    });

  } catch (error: any) {
    console.error('❌ Error in /api/ray:', error);
    return res.status(500).json({
      error: 'Internal server error',
      message: error.message || 'An unexpected error occurred'
    });
  }
}
