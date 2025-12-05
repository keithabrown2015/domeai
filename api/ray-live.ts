import type { VercelRequest, VercelResponse } from '@vercel/node';

// SHORT-TERM CONVERSATIONAL MEMORY CONSTANTS
const MAX_HISTORY_MESSAGES = 14;

type ChatMessage = { role: "system" | "user" | "assistant"; content: string };

// Helper function to extract content from OpenAI response
function extractContent(responseData: any): string {
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
}

// Build messages array with system prompt and conversation history
function buildChatMessages(options: {
  systemPrompt: string;
  conversationHistory: ChatMessage[] | undefined | null;
  newUserMessage: string;
}): ChatMessage[] {
  const { systemPrompt, conversationHistory, newUserMessage } = options;

  const safeHistory = Array.isArray(conversationHistory)
    ? conversationHistory
    : [];

  // keep only the most recent messages
  const trimmedHistory = safeHistory.slice(-MAX_HISTORY_MESSAGES);

  const messages: ChatMessage[] = [
    { role: "system", content: systemPrompt },
    ...trimmedHistory,
    { role: "user", content: newUserMessage },
  ];

  return messages;
}

// Helper function to format userProfile string for system prompt
function formatUserProfile(userProfile: string | undefined): string {
  if (!userProfile || userProfile.trim().length === 0) {
    return '';
  }
  
  return `\n\nUSER PROFILE (stable personal facts you always remember):\n${userProfile.trim()}\n\nThese facts persist across all conversations. Use them naturally when relevant, but don't repeat them unnecessarily.`;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  try {
    // App token gate - check at the very top
    const appToken = req.headers['x-ray-app-token'];
    if (!appToken || appToken !== process.env.APP_TOKEN) {
      return res.status(401).json({ 
        ok: false, 
        tier: 3,
        model: 'ray-live-error',
        message: 'Unauthorized',
        reasoning: null,
        sources: []
      });
    }

    // Only accept POST requests
    if (req.method !== 'POST') {
      return res.status(405).json({
        ok: false,
        tier: 3,
        model: 'ray-live-error',
        message: 'Only POST requests are accepted',
        reasoning: null,
        sources: []
      });
    }

    console.log('🌐 ray-live: Received request');
    console.log('🌐 ray-live: conversationHistory:', JSON.stringify(req.body.conversationHistory || [], null, 2));
    console.log('🌐 ray-live: query:', req.body.query);
    
    // Parse request body (same format as /api/ray)
    const { query, conversationHistory, userProfile } = req.body;

    if (!query || typeof query !== 'string') {
      return res.status(400).json({
        ok: false,
        tier: 3,
        model: 'ray-live-error',
        message: 'Missing or invalid "query" field in request body',
        reasoning: null,
        sources: []
      });
    }

    const userQuery = query;

    // Check for OpenAI API key
    const openaiApiKey = process.env.OPENAI_API_KEY;
    if (!openaiApiKey) {
      console.error('❌ OPENAI_API_KEY not found in environment variables');
      return res.status(500).json({
        ok: false,
        tier: 3,
        model: 'ray-live-error',
        message: 'Ray had a problem talking to OpenAI. Please try again in a minute.',
        reasoning: null,
        sources: []
      });
    }

    // Prepare conversationHistory
    const conversationHistoryArray: ChatMessage[] | undefined = Array.isArray(conversationHistory)
      ? conversationHistory.map(msg => ({
          role: msg.role as "user" | "assistant" | "system",
          content: String(msg.content || '')
        }))
      : undefined;

    // Get current date for system prompt
    const now = new Date();
    const isoNow = now.toISOString();
    const today = new Date().toLocaleDateString('en-US', { 
      weekday: 'long', 
      year: 'numeric', 
      month: 'long', 
      day: 'numeric' 
    });

    // Build system prompt with userProfile
    const userProfileSection = formatUserProfile(userProfile);
    const systemPrompt = `You are Ray, a helpful, reliable AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.${userProfileSection}

Today is ${today}. Today's date is: ${isoNow}. Interpret 'this week', 'yesterday', 'last night' relative to this date.

You excel at answering questions about current events, news, live data, recent happenings, and real-time information.

WHEN TO USE web_search TOOL:
- Only use web_search when the user asks about "today", "this week", "current", "live", "latest", "recent", or similar time-sensitive terms
- Only use web_search when the answer depends on recent information that you wouldn't know from your training data
- For general knowledge questions that don't require current information, answer directly without web_search

CRITICAL RULES FOR web_search TOOL:
- Do NOT default to the year 2023 or any past year
- Only include a specific year in the search query if the user explicitly mentions that year
- For 'this week' queries, use today's date (${isoNow}) to determine the correct timeframe
- When building search queries, focus on the topic and use relative time words (this week, today, recent) rather than specific dates unless the user provided them
- Example: For "this week's Monday Night Football game", build a query like "NFL Monday Night Football this week" or "NFL Monday Night Football score and teams" - do NOT add hard-coded dates

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

You have access to the recent conversation history below (last ${MAX_HISTORY_MESSAGES} messages). Use it to maintain context and answer questions that reference previous messages.`;

    // Build input array for Responses API
    const inputMessages: Array<{ role: string; content: string }> = [];
    
    // Add system prompt
    inputMessages.push({
      role: 'system',
      content: systemPrompt
    });
    
    // Add conversation history
    if (conversationHistoryArray && conversationHistoryArray.length > 0) {
      inputMessages.push(...conversationHistoryArray);
    }
    
    // Add current user message
    inputMessages.push({
      role: 'user',
      content: userQuery
    });

    console.log('🌐 ray-live: Calling OpenAI Responses API with web_search tool');
    console.log('🌐 ray-live: Model: gpt-4o-mini');
    console.log('🌐 ray-live: Input messages count:', inputMessages.length);

    // Call OpenAI Responses API with web_search tool
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${openaiApiKey}`
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        tools: [{ type: 'web_search_preview' }],
        input: inputMessages
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('❌ ray-live: Responses API error:', response.status, errorText);
      throw new Error(`OpenAI Responses API error: ${response.status} - ${errorText}`);
    }

    const responseData = await response.json();
    console.log('📦 ray-live: Responses API response received');
    
    // Extract the final answer text, ignoring web_search_call objects
    // Look at response.output, then item.content, find LAST output_text (after tool calls)
    let replyText = "Sorry, I couldn't find an answer.";
    
    // Handle different possible response structures
    const outputArray = Array.isArray(responseData?.output) 
      ? responseData.output 
      : (responseData?.output ? [responseData.output] : []);
    
    // Collect all output_text items (we want the LAST one, after tool calls)
    const textItems: string[] = [];
    
    // Scan through all output items
    for (const item of outputArray) {
      if (!item || typeof item !== 'object') continue;
      
      // Check if item has content array
      const contentArray = Array.isArray(item.content) ? item.content : [];
      
      // Scan through content array
      for (const c of contentArray) {
        if (!c || typeof c !== 'object') continue;
        
        // Log web_search calls for observability
        if (c.type === "web_search_call") {
          const searchQuery = c.action?.query || c.query || 'unknown';
          console.log(`[web_search] ${new Date().toISOString()} | query: "${searchQuery}"`);
          continue;
        }
        
        // Skip other tool call objects
        if (c.type === "tool_call" || c.type === "tool_use") {
          continue;
        }
        
        // Collect output_text items
        if (c.type === "output_text" && typeof c.text === "string" && c.text.trim().length > 0) {
          const textValue = c.text.trim();
          // Ensure we're not accidentally getting a JSON string
          if (!textValue.startsWith('{') || !textValue.includes('"type":"web_search_call"')) {
            textItems.push(textValue);
          }
        }
      }
    }
    
    // Use the LAST output_text item (final answer comes after tool calls)
    if (textItems.length > 0) {
      replyText = textItems[textItems.length - 1];
    }

    // Final validation: ensure we have actual text, not JSON or empty string
    const trimmedReply = replyText.trim();
    if (replyText === "Sorry, I couldn't find an answer." || 
        trimmedReply.length === 0 ||
        (trimmedReply.startsWith('{') && trimmedReply.includes('"type":"web_search_call"'))) {
      console.error('❌ ray-live: Could not extract answer text from response');
      console.error('❌ ray-live: Response structure:', JSON.stringify(responseData).substring(0, 2000));
      throw new Error('No reply text found in Responses API response');
    }
    
    // Final safety check: ensure replyText is a clean string, not a JSON object
    replyText = trimmedReply;

    // Extract sources from Responses API
    let sources: string[] = [];
    if (responseData.sources && Array.isArray(responseData.sources)) {
      sources = responseData.sources;
    } else {
      // Fallback: try to extract URLs from the reply text
      const urlRegex = /https?:\/\/[^\s]+/g;
      const matches = replyText.match(urlRegex);
      if (matches) {
        sources = matches.slice(0, 5);
      }
    }

    console.log("ray-live reply:", replyText.substring(0, 200));
    console.log('✅ ray-live: Sources count:', sources.length);

    // Return response in same format as /api/ray (matching exact shape)
    return res.status(200).json({
      ok: true,
      tier: 3,
      model: 'gpt-4o-mini-web-search',
      message: replyText,
      reasoning: 'Using OpenAI Responses API with web_search tool for live data',
      sources: sources
    });

  } catch (error: any) {
    console.error('ray-live error', error);
    return res.status(500).json({
      ok: false,
      tier: 3,
      model: 'ray-live-error',
      message: 'Ray had a problem talking to OpenAI. Please try again in a minute.',
      reasoning: null,
      sources: []
    });
  }
}

