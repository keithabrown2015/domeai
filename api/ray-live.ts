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
  // Only accept POST requests
  if (req.method !== 'POST') {
    return res.status(405).json({ 
      error: 'Method not allowed', 
      message: 'Only POST requests are accepted' 
    });
  }

  // NOTE: /api/ray-live does NOT require X-App-Token for easy testing
  // This is intentional - /api/ray still requires it for production use

  try {
    console.log('🌐 ray-live: Received request');
    console.log('🌐 ray-live: conversationHistory:', JSON.stringify(req.body.conversationHistory || [], null, 2));
    console.log('🌐 ray-live: query:', req.body.query);
    
    // Parse request body (same format as /api/ray)
    const { query, conversationHistory, userProfile } = req.body;

    if (!query || typeof query !== 'string') {
      return res.status(400).json({ 
        error: 'Bad request', 
        message: 'Missing or invalid "query" field in request body' 
      });
    }

    const userQuery = query;

    // Check for OpenAI API key
    const openaiApiKey = process.env.OPENAI_API_KEY;
    if (!openaiApiKey) {
      console.error('❌ OPENAI_API_KEY not found in environment variables');
      return res.status(500).json({ 
        error: 'Server configuration error', 
        message: 'OpenAI API key is not configured' 
      });
    }

    // Prepare conversationHistory
    const conversationHistoryArray: ChatMessage[] | undefined = Array.isArray(conversationHistory)
      ? conversationHistory.map(msg => ({
          role: msg.role as "user" | "assistant" | "system",
          content: String(msg.content || '')
        }))
      : undefined;

    // Build system prompt with userProfile
    const userProfileSection = formatUserProfile(userProfile);
    const systemPrompt = `You are Ray, a helpful, reliable AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.${userProfileSection}

You excel at answering questions about current events, news, live data, recent happenings, and real-time information. Use web search to find the most current information available.

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
        tools: [{ type: 'web_search' }],
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
    console.log('📦 ray-live: Response structure keys:', Object.keys(responseData));
    
    // Extract the first text output from the Responses API result
    let replyText = "Sorry, I couldn't generate a reply.";

    const firstOutput = responseData?.output?.[0];
    const firstContent = firstOutput?.content?.[0];

    if (firstContent && firstContent.type === "output_text" && firstContent.text) {
      replyText = firstContent.text;
    } else if (typeof responseData?.output_text === "string") {
      // Fallback if SDK exposes output_text directly
      replyText = responseData.output_text;
    } else if (firstContent && typeof firstContent === "string") {
      replyText = firstContent;
    } else if (firstContent && firstContent.text && typeof firstContent.text === "string") {
      replyText = firstContent.text;
    } else if (firstContent && firstContent.message && typeof firstContent.message === "string") {
      replyText = firstContent.message;
    } else {
      console.error('❌ ray-live: Could not extract text from response structure');
      console.error('❌ ray-live: firstOutput:', JSON.stringify(firstOutput).substring(0, 500));
      console.error('❌ ray-live: firstContent:', JSON.stringify(firstContent).substring(0, 500));
      throw new Error('Could not extract reply text from Responses API response');
    }

    if (!replyText || replyText.trim().length === 0) {
      throw new Error('No reply text found in Responses API response');
    }

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

    console.log('✅ ray-live: Reply generated:', replyText.substring(0, 100));
    console.log('✅ ray-live: Sources count:', sources.length);

    // Return response in same format as /api/ray
    return res.status(200).json({
      ok: true,
      tier: 3,
      model: 'gpt-4o-mini-web-search',
      message: replyText,
      reasoning: 'Using OpenAI Responses API with web_search tool for live data',
      sources: sources
    });

  } catch (error: any) {
    console.error('❌ ray-live error:', error);
    console.error('❌ ray-live error stack:', error.stack);
    return res.status(500).json({
      error: 'Internal server error',
      message: error.message || 'An unexpected error occurred'
    });
  }
}

