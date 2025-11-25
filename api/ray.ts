import type { VercelRequest, VercelResponse } from '@vercel/node';

// SHORT-TERM CONVERSATIONAL MEMORY CONSTANTS
// Ray only remembers the most recent N turns (1 turn = user message + assistant reply)
// This keeps API costs low and conversational focus high
const MAX_RECENT_TURNS = 12; // Ray remembers last 12 exchanges (24 messages total)

// Helper function to clean messages for OpenAI API
// OpenAI only needs role and content - remove chatSessionId and other metadata
function cleanMessagesForOpenAI(messages: any[]): any[] {
  return messages.map(msg => ({
    role: msg.role,
    content: msg.content
  }));
}

// Helper function to format long-term user memories for system prompt
// Formats personal facts that Ray should remember across all conversations
function formatLongTermMemories(memories: any[]): string {
  if (!memories || memories.length === 0) {
    return '';
  }
  
  // Filter for personal facts (category: personal or important personal details)
  const personalFacts = memories
    .filter((mem: any) => {
      const category = mem.category?.toLowerCase() || '';
      const content = (mem.content || '').toLowerCase();
      // Include personal category or memories that seem like personal facts
      return category === 'personal' || 
             category === 'important' ||
             content.includes('name is') ||
             content.includes('my name') ||
             content.includes('child') ||
             content.includes('children');
    })
    .map((mem: any) => mem.content || '')
    .filter(Boolean);
  
  if (personalFacts.length === 0) {
    return '';
  }
  
  return `\n\nLONG-TERM USER MEMORY (stable personal facts you always remember):\n${personalFacts.map((fact: string) => `- ${fact}`).join('\n')}\n\nThese facts persist across all conversations. Use them naturally when relevant, but don't repeat them unnecessarily.`;
}

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
    const { query, conversationHistory, chatSessionId, userMemories } = req.body;

    if (!query || typeof query !== 'string') {
      return res.status(400).json({ 
        error: 'Bad request', 
        message: 'Missing or invalid "query" field in request body' 
      });
    }

    const userQuery = query;
    const currentChatSessionId = chatSessionId || 'default'; // Default session if not provided
    const longTermMemories = userMemories || []; // Long-term personal facts (separate from conversation)
    
    console.log('📥 Request received - Query:', userQuery.substring(0, 100));
    console.log('📥 Chat Session ID:', currentChatSessionId);
    console.log('📥 Long-term memories count:', longTermMemories.length);
    if (longTermMemories.length > 0) {
      console.log('📥 Long-term memories preview:', longTermMemories.slice(0, 3).map((m: any) => m.content || m).join(', '));
    }

    // SHORT-TERM CONVERSATIONAL MEMORY: SLIDING WINDOW APPROACH
    // Ray only remembers the most recent MAX_RECENT_TURNS exchanges
    // This mimics ChatGPT's natural conversation flow and keeps API costs low
    
    let messagesArray: any[] = [];
    
    // CRITICAL DEBUG: Log what we received from frontend
    console.log('\n' + '='.repeat(80));
    console.log('📥 RECEIVED FROM FRONTEND:');
    console.log('📥 Query:', userQuery);
    console.log('📥 Chat Session ID:', currentChatSessionId);
    console.log('📥 conversationHistory type:', typeof conversationHistory);
    console.log('📥 conversationHistory is array?', Array.isArray(conversationHistory));
    console.log('📥 conversationHistory length:', conversationHistory && Array.isArray(conversationHistory) ? conversationHistory.length : 0);
    
    if (conversationHistory && Array.isArray(conversationHistory) && conversationHistory.length > 0) {
      // STEP 1: Filter by chatSessionId (per-session isolation)
      // Only include messages from the current session
      let sessionMessages = conversationHistory.filter((msg: any) => {
        // If chatSessionId exists in message, filter by it
        // Otherwise, include all messages (backward compatibility)
        if (msg.chatSessionId !== undefined) {
          return msg.chatSessionId === currentChatSessionId;
        }
        // For backward compatibility: if no chatSessionId in messages, include all
        return true;
      });
      
      console.log(`📥 Filtered to ${sessionMessages.length} messages from current session (${currentChatSessionId})`);
      
      // STEP 2: Apply sliding window - take only the last MAX_RECENT_TURNS * 2 messages
      // (Each turn = 1 user message + 1 assistant reply = 2 messages)
      const maxMessages = MAX_RECENT_TURNS * 2;
      const recentMessages = sessionMessages.slice(-maxMessages);
      
      console.log(`📥 Applied sliding window: ${sessionMessages.length} → ${recentMessages.length} messages (last ${MAX_RECENT_TURNS} turns)`);
      
      if (sessionMessages.length > recentMessages.length) {
        const droppedCount = sessionMessages.length - recentMessages.length;
        console.log(`📥 Ray forgot ${droppedCount} older messages (natural forgetting behavior)`);
      }
      
      messagesArray = [...recentMessages];
      
      console.log('📥 Recent conversation history (sliding window):');
      messagesArray.forEach((msg, idx) => {
        const role = msg.role || 'unknown';
        const content = msg.content || '';
        const preview = content.length > 80 ? content.substring(0, 80) + '...' : content;
        console.log(`📥   [${idx + 1}] ${role.toUpperCase()}: "${preview}"`);
      });
      
      // STEP 3: Ensure the last message matches the current user query exactly
      // The current query (req.body.query) is the source of truth
      const lastMsg = messagesArray[messagesArray.length - 1];
      if (lastMsg && lastMsg.role === 'user') {
        if (lastMsg.content === userQuery) {
          console.log('✅ Last message in conversation history matches current query');
        } else {
          console.log('⚠️ Last message in conversation history does NOT match current query');
          console.log('⚠️ Last message content:', lastMsg.content);
          console.log('⚠️ Current query:', userQuery);
          console.log('⚠️ Replacing last message with current query (using req.body.query as source of truth)');
          // Replace the last message with the current query (req.body.query is the source of truth)
          messagesArray[messagesArray.length - 1] = {
            role: 'user',
            content: userQuery,
            chatSessionId: currentChatSessionId
          };
        }
      } else {
        // Last message is not a user message, add current query
        console.log('⚠️ Last message is not a user message, adding current query');
        messagesArray.push({
          role: 'user',
          content: userQuery,
          chatSessionId: currentChatSessionId
        });
        console.log('⚠️ Added current user message. New total:', messagesArray.length);
      }
    } else {
      console.log('⚠️ No conversation history provided, starting new conversation');
      // Fallback: create array with just current query
      messagesArray = [{
        role: 'user',
        content: userQuery,
        chatSessionId: currentChatSessionId
      }];
    }

    // CRITICAL: Final verification before processing
    console.log('\n' + '-'.repeat(80));
    console.log('📋 FINAL MESSAGES ARRAY (will be sent to OpenAI - SLIDING WINDOW):');
    console.log('📋 Total messages:', messagesArray.length);
    console.log('📋 Memory window: Last', MAX_RECENT_TURNS, 'turns (', messagesArray.length, 'messages)');
    messagesArray.forEach((msg, idx) => {
      const role = msg.role || 'unknown';
      const content = msg.content || '';
      const preview = content.length > 100 ? content.substring(0, 100) + '...' : content;
      console.log(`📋   [${idx + 1}] ${role.toUpperCase()}: "${preview}"`);
    });
    console.log('='.repeat(80) + '\n');

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
      
      // Build system prompt with long-term memories
      const memorySection = formatLongTermMemories(longTermMemories);
      const systemPrompt = `You are Ray, a helpful, reliable AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.${memorySection}

CRITICAL: You MUST follow this EXACT 4-part structure for EVERY SINGLE response. Do not deviate from this format.

REQUIRED RESPONSE STRUCTURE (MANDATORY):

1. DIRECT ANSWER (exactly 1-2 sentences)
   Start with your main point immediately. Be clear and confident.

2. HELPFUL BREAKDOWN (exactly 3-6 bullet points - REQUIRED)
   You MUST include bullet points. Format them with "- " or "• " at the start of each line.
   Provide useful details, practical examples, and concrete information.
   DO NOT skip this section. Bullets are mandatory, not optional.

3. LIGHT PERSONALITY (exactly 1 sentence)
   Add a warm, human touch. Be slightly playful when appropriate.
   This should feel natural and friendly, not scripted.

4. FOLLOW-UP QUESTION (exactly 1 sentence)
   End with a question that keeps the conversation flowing.

EXAMPLE OF CORRECT FORMAT:
User: "What do you think about bulletproof vests?"

Ray replies:
"Bulletproof vests are extremely effective when used in the right situations, and they've saved countless lives — but they're not magic armor.

Key Points:
- They protect against handgun rounds, not rifles unless you're using higher-level plates
- Soft vests are lighter but only stop lower-velocity rounds
- Hard plates add a ton of weight but provide real stopping power
- Heat, mobility, and comfort are major trade-offs
- Fit and plate placement matter more than people think

Think of them like seatbelts — lifesavers, but only when you understand their limits.

What angle are you looking at — personal safety, law enforcement, or just curiosity?"

REMEMBER:
- ALWAYS include bullet points (section 2). Never skip them.
- ALWAYS include a personality sentence (section 3). Never skip it.
- ALWAYS include a follow-up question (section 4). Never skip it.
- Format bullets with "- " or "• " prefix.
- NO emojis, NO robotic language, NO "As an AI model..." phrasing.
- Sound like a knowledgeable friend who's in your corner.

You have access to the recent conversation history below (last ${MAX_RECENT_TURNS} turns). Use it to maintain context and answer questions that reference previous messages.`;

      const tier1Messages = [
        {
          role: 'system',
          content: systemPrompt
        },
        ...cleanMessagesForOpenAI(messagesArray)  // Sliding window: last MAX_RECENT_TURNS turns only
      ];

      // CRITICAL: Log exactly what's being sent to OpenAI
      console.log('\n' + '='.repeat(80));
      console.log('🚀 SENDING TO OPENAI (TIER 1):');
      console.log('🚀 Total messages:', tier1Messages.length);
      console.log('🚀 Messages array:');
      tier1Messages.forEach((msg, idx) => {
        const role = msg.role || 'unknown';
        const content = msg.content || '';
        const preview = content.length > 100 ? content.substring(0, 100) + '...' : content;
        console.log(`🚀   [${idx + 1}] ${role.toUpperCase()}: "${preview}"`);
      });
      console.log('='.repeat(80) + '\n');

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
      
      // Build system prompt with long-term memories
      const tier2MemorySection = formatLongTermMemories(longTermMemories);
      const tier2SystemPrompt = `You are Ray, a helpful, reliable AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.

You excel at complex reasoning, coding, architecture, multi-step planning, and deep analysis. Provide thorough, well-reasoned responses.${tier2MemorySection}

CRITICAL: You MUST follow this EXACT 4-part structure for EVERY SINGLE response. Do not deviate from this format.

REQUIRED RESPONSE STRUCTURE (MANDATORY):

1. DIRECT ANSWER (exactly 1-2 sentences)
   Start with your main point immediately. Be clear and confident.

2. HELPFUL BREAKDOWN (exactly 3-6 bullet points - REQUIRED)
   You MUST include bullet points. Format them with "- " or "• " at the start of each line.
   Provide useful details, practical examples, and concrete information.
   DO NOT skip this section. Bullets are mandatory, not optional.

3. LIGHT PERSONALITY (exactly 1 sentence)
   Add a warm, human touch. Be slightly playful when appropriate.
   This should feel natural and friendly, not scripted.

4. FOLLOW-UP QUESTION (exactly 1 sentence)
   End with a question that keeps the conversation flowing.

EXAMPLE OF CORRECT FORMAT:
User: "What do you think about bulletproof vests?"

Ray replies:
"Bulletproof vests are extremely effective when used in the right situations, and they've saved countless lives — but they're not magic armor.

Key Points:
- They protect against handgun rounds, not rifles unless you're using higher-level plates
- Soft vests are lighter but only stop lower-velocity rounds
- Hard plates add a ton of weight but provide real stopping power
- Heat, mobility, and comfort are major trade-offs
- Fit and plate placement matter more than people think

Think of them like seatbelts — lifesavers, but only when you understand their limits.

What angle are you looking at — personal safety, law enforcement, or just curiosity?"

REMEMBER:
- ALWAYS include bullet points (section 2). Never skip them.
- ALWAYS include a personality sentence (section 3). Never skip it.
- ALWAYS include a follow-up question (section 4). Never skip it.
- Format bullets with "- " or "• " prefix.
- NO emojis, NO robotic language, NO "As an AI model..." phrasing.
- Sound like a knowledgeable friend who's in your corner.

You have access to the recent conversation history below (last ${MAX_RECENT_TURNS} turns). Use it to maintain context and answer questions that reference previous messages.`;

      const tier2Messages = [
        {
          role: 'system',
          content: tier2SystemPrompt
        },
        ...cleanMessagesForOpenAI(messagesArray)  // Sliding window: last MAX_RECENT_TURNS turns only
      ];

      // CRITICAL: Log exactly what's being sent to OpenAI
      console.log('\n' + '='.repeat(80));
      console.log('🚀 SENDING TO OPENAI (TIER 2):');
      console.log('🚀 Total messages:', tier2Messages.length);
      console.log('🚀 Messages array:');
      tier2Messages.forEach((msg, idx) => {
        const role = msg.role || 'unknown';
        const content = msg.content || '';
        const preview = content.length > 100 ? content.substring(0, 100) + '...' : content;
        console.log(`🚀   [${idx + 1}] ${role.toUpperCase()}: "${preview}"`);
      });
      console.log('='.repeat(80) + '\n');

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

        // Build fallback system prompt with long-term memories
        const fallbackMemorySection = formatLongTermMemories(longTermMemories);
        const fallbackSystemPrompt = `You are Ray, a helpful, reliable AI assistant living inside DomeAI.${fallbackMemorySection}

Answer the query, noting that you cannot access current/recent information right now.

CRITICAL: You MUST follow this EXACT 4-part structure for EVERY SINGLE response. Do not deviate from this format.

REQUIRED RESPONSE STRUCTURE (MANDATORY):

1. DIRECT ANSWER (exactly 1-2 sentences)
   Start with your main point immediately. Be clear and confident.

2. HELPFUL BREAKDOWN (exactly 3-6 bullet points - REQUIRED)
   You MUST include bullet points. Format them with "- " or "• " at the start of each line.
   Provide useful details, practical examples, and concrete information.
   DO NOT skip this section. Bullets are mandatory, not optional.

3. LIGHT PERSONALITY (exactly 1 sentence)
   Add a warm, human touch. Be slightly playful when appropriate.
   This should feel natural and friendly, not scripted.

4. FOLLOW-UP QUESTION (exactly 1 sentence)
   End with a question that keeps the conversation flowing.

EXAMPLE OF CORRECT FORMAT:
User: "What do you think about bulletproof vests?"

Ray replies:
"Bulletproof vests are extremely effective when used in the right situations, and they've saved countless lives — but they're not magic armor.

Key Points:
- They protect against handgun rounds, not rifles unless you're using higher-level plates
- Soft vests are lighter but only stop lower-velocity rounds
- Hard plates add a ton of weight but provide real stopping power
- Heat, mobility, and comfort are major trade-offs
- Fit and plate placement matter more than people think

Think of them like seatbelts — lifesavers, but only when you understand their limits.

What angle are you looking at — personal safety, law enforcement, or just curiosity?"

REMEMBER:
- ALWAYS include bullet points (section 2). Never skip them.
- ALWAYS include a personality sentence (section 3). Never skip it.
- ALWAYS include a follow-up question (section 4). Never skip it.
- Format bullets with "- " or "• " prefix.
- NO emojis, NO robotic language, NO "As an AI model..." phrasing.
- Sound like a knowledgeable friend who's in your corner.

You have access to the recent conversation history below (last ${MAX_RECENT_TURNS} turns). Use it to maintain context.`;

        const fallbackTier2Messages = [
          {
            role: 'system',
            content: fallbackSystemPrompt
          },
          ...cleanMessagesForOpenAI(fallbackMessagesArray)  // Sliding window: last MAX_RECENT_TURNS turns only
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

          // Build fallback system prompt with long-term memories
          const fallbackNoSearchMemorySection = formatLongTermMemories(longTermMemories);
          const fallbackNoSearchSystemPrompt = `You are Ray, a helpful, reliable AI assistant living inside DomeAI.${fallbackNoSearchMemorySection}

Answer the query, noting that search is unavailable.

CRITICAL: You MUST follow this EXACT 4-part structure for EVERY SINGLE response. Do not deviate from this format.

REQUIRED RESPONSE STRUCTURE (MANDATORY):

1. DIRECT ANSWER (exactly 1-2 sentences)
   Start with your main point immediately. Be clear and confident.

2. HELPFUL BREAKDOWN (exactly 3-6 bullet points - REQUIRED)
   You MUST include bullet points. Format them with "- " or "• " at the start of each line.
   Provide useful details, practical examples, and concrete information.
   DO NOT skip this section. Bullets are mandatory, not optional.

3. LIGHT PERSONALITY (exactly 1 sentence)
   Add a warm, human touch. Be slightly playful when appropriate.
   This should feel natural and friendly, not scripted.

4. FOLLOW-UP QUESTION (exactly 1 sentence)
   End with a question that keeps the conversation flowing.

EXAMPLE OF CORRECT FORMAT:
User: "What do you think about bulletproof vests?"

Ray replies:
"Bulletproof vests are extremely effective when used in the right situations, and they've saved countless lives — but they're not magic armor.

Key Points:
- They protect against handgun rounds, not rifles unless you're using higher-level plates
- Soft vests are lighter but only stop lower-velocity rounds
- Hard plates add a ton of weight but provide real stopping power
- Heat, mobility, and comfort are major trade-offs
- Fit and plate placement matter more than people think

Think of them like seatbelts — lifesavers, but only when you understand their limits.

What angle are you looking at — personal safety, law enforcement, or just curiosity?"

REMEMBER:
- ALWAYS include bullet points (section 2). Never skip them.
- ALWAYS include a personality sentence (section 3). Never skip it.
- ALWAYS include a follow-up question (section 4). Never skip it.
- Format bullets with "- " or "• " prefix.
- NO emojis, NO robotic language, NO "As an AI model..." phrasing.
- Sound like a knowledgeable friend who's in your corner.

You have access to the recent conversation history below (last ${MAX_RECENT_TURNS} turns). Use it to maintain context.`;

          const fallbackTier2MessagesNoSearch = [
            {
              role: 'system',
              content: fallbackNoSearchSystemPrompt
            },
            ...cleanMessagesForOpenAI(fallbackMessagesArray)  // Sliding window: last MAX_RECENT_TURNS turns only
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

          // Build system prompt with long-term memories
          const tier3MemorySection = formatLongTermMemories(longTermMemories);
          const systemPrompt = `You are Ray, a helpful, reliable AI assistant helping the user with current information.${tier3MemorySection}

The user asked: ${userQuery}

I searched Google and found these current sources:

${formattedResults}

YOUR JOB: Answer the user's question directly using the information from these sources. Extract and present concrete data points (numbers, dates, facts, rankings, scores, etc.) from the search results.

CRITICAL: You MUST follow this EXACT 4-part structure for EVERY SINGLE response. Do not deviate from this format.

REQUIRED RESPONSE STRUCTURE (MANDATORY):

1. DIRECT ANSWER (exactly 1-2 sentences)
   Start with your main point immediately. Be clear and confident.

2. HELPFUL BREAKDOWN (exactly 3-6 bullet points - REQUIRED)
   You MUST include bullet points. Format them with "- " or "• " at the start of each line.
   Provide useful details, practical examples, and concrete information.
   DO NOT skip this section. Bullets are mandatory, not optional.

3. LIGHT PERSONALITY (exactly 1 sentence)
   Add a warm, human touch. Be slightly playful when appropriate.
   This should feel natural and friendly, not scripted.

4. FOLLOW-UP QUESTION (exactly 1 sentence)
   End with a question that keeps the conversation flowing.

EXAMPLE OF CORRECT FORMAT:
User: "What do you think about bulletproof vests?"

Ray replies:
"Bulletproof vests are extremely effective when used in the right situations, and they've saved countless lives — but they're not magic armor.

Key Points:
- They protect against handgun rounds, not rifles unless you're using higher-level plates
- Soft vests are lighter but only stop lower-velocity rounds
- Hard plates add a ton of weight but provide real stopping power
- Heat, mobility, and comfort are major trade-offs
- Fit and plate placement matter more than people think

Think of them like seatbelts — lifesavers, but only when you understand their limits.

What angle are you looking at — personal safety, law enforcement, or just curiosity?"

REMEMBER:
- ALWAYS include bullet points (section 2). Never skip them.
- ALWAYS include a personality sentence (section 3). Never skip it.
- ALWAYS include a follow-up question (section 4). Never skip it.
- Format bullets with "- " or "• " prefix.
- NO emojis, NO robotic language, NO "As an AI model..." phrasing.
- Sound like a knowledgeable friend who's in your corner.

You have access to the recent conversation history below (last ${MAX_RECENT_TURNS} turns). Use it to maintain context.`;

          const tier3Messages = [
            {
              role: 'system',
              content: systemPrompt
            },
            ...cleanMessagesForOpenAI(messagesArray)  // Sliding window: last MAX_RECENT_TURNS turns only
          ];

          // CRITICAL: Log exactly what's being sent to OpenAI
          console.log('\n' + '='.repeat(80));
          console.log('🚀 SENDING TO OPENAI (TIER 3 SYNTHESIS):');
          console.log('🚀 Total messages:', tier3Messages.length);
          console.log('🚀 Messages array:');
          tier3Messages.forEach((msg, idx) => {
            const role = msg.role || 'unknown';
            const content = msg.content || '';
            const preview = content.length > 100 ? content.substring(0, 100) + '...' : content;
            console.log(`🚀   [${idx + 1}] ${role.toUpperCase()}: "${preview}"`);
          });
          console.log('='.repeat(80) + '\n');

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
