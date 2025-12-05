import type { VercelRequest, VercelResponse } from '@vercel/node';
import { sendRayEmail } from './lib/email/sendRayEmail';
import { supabaseAdmin } from './lib/supabaseAdmin';

// SHORT-TERM CONVERSATIONAL MEMORY CONSTANTS
// Ray only remembers the most recent N messages (not entire conversation history)
// This keeps API costs low and conversational focus high
const MAX_HISTORY_MESSAGES = 14; // Only send the last 14 messages to OpenAI

type ChatMessage = { role: "system" | "user" | "assistant"; content: string };

// Helper function to detect if user requested email
function userRequestedEmail(userMessage: string): boolean {
  const lowered = userMessage.toLowerCase();
  return (
    lowered.includes("email that to me") ||
    lowered.includes("email this to me") ||
    lowered.includes("send that to my email") ||
    lowered.includes("send this to my email") ||
    lowered.includes("email those instructions") ||
    lowered.includes("email these instructions")
  );
}

// Helper function to answer user question ALWAYS using OpenAI Responses API with web_search tool
async function answerUserQuestionWithWebSearch(
  userMessage: string,
  conversationHistory: ChatMessage[] | undefined,
  systemPrompt: string,
  openaiApiKey: string,
  model: string = 'gpt-4o-mini'
): Promise<{ message: string; sources: string[] }> {
  console.log("Ray called OpenAI with web_search for this message:", userMessage.substring(0, 100));

  // Try Responses API first, but fallback gracefully to Chat Completions
  try {
    // Build input array with system prompt and conversation history
    const inputMessages: Array<{ role: string; content: string }> = [];
    
    // Add system prompt if provided
    if (systemPrompt) {
      inputMessages.push({
        role: 'system',
        content: systemPrompt
      });
    }
    
    // Add conversation history
    if (conversationHistory && conversationHistory.length > 0) {
      inputMessages.push(...conversationHistory);
    }
    
    // Add current user message
    inputMessages.push({
      role: 'user',
      content: userMessage
    });
    
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${openaiApiKey}`
      },
      body: JSON.stringify({
        model: model,
        tools: [{ type: 'web_search' }],
        input: inputMessages
      })
    });

    if (response.ok) {
      const responseData = await response.json();
      console.log('📦 Responses API response structure:', JSON.stringify(responseData).substring(0, 500));
      
      // Try multiple ways to extract the text
      let text: string = '';
      let sources: string[] = [];
      
      // Method 1: Check for output_text directly
      if (responseData.output_text && typeof responseData.output_text === 'string') {
        text = responseData.output_text;
      }
      // Method 2: Check for output array with content
      else if (responseData.output && Array.isArray(responseData.output) && responseData.output.length > 0) {
        const firstOutput = responseData.output[0];
        if (firstOutput.content && Array.isArray(firstOutput.content) && firstOutput.content.length > 0) {
          const firstContent = firstOutput.content[0];
          if (firstContent.type === 'output_text' && firstContent.text) {
            text = firstContent.text;
          } else if (firstContent.message && typeof firstContent.message === 'string') {
            text = firstContent.message;
          } else if (typeof firstContent === 'string') {
            text = firstContent;
          } else {
            text = JSON.stringify(firstContent);
          }
        } else if (firstOutput.text && typeof firstOutput.text === 'string') {
          text = firstOutput.text;
        } else if (typeof firstOutput === 'string') {
          text = firstOutput;
        }
      }
      // Method 3: Check for message field
      else if (responseData.message && typeof responseData.message === 'string') {
        text = responseData.message;
      }
      
      // Extract sources
      if (responseData.sources && Array.isArray(responseData.sources)) {
        sources = responseData.sources;
      }
      
      if (text) {
        console.log('✅ OpenAI Responses API with web_search completed');
        return { message: text, sources };
      } else {
        console.warn('⚠️ Responses API returned OK but no text found, falling back');
        throw new Error('No text found in Responses API response');
      }
    } else {
      // Responses API returned error
      const errorText = await response.text().catch(() => 'Unknown error');
      console.error(`❌ Responses API error: ${response.status} - ${errorText}`);
      throw new Error(`Responses API returned ${response.status}: ${errorText}`);
    }
  } catch (error: any) {
    console.log('⚠️ Responses API not available or failed, falling back to Chat Completions');
    console.error('OpenAI error in Ray handler:', error);
    
    // Fallback: Use Chat Completions API with web search instructions
    try {
      const messages = buildChatMessages({
        systemPrompt: systemPrompt + '\n\nIMPORTANT: Use current, up-to-date information from web sources when answering. Search the web for recent information if needed.',
        conversationHistory,
        newUserMessage: userMessage
      });

      const chatResponse = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${openaiApiKey}`
        },
        body: JSON.stringify({
          model: model,
          messages,
          temperature: 0.7,
          max_tokens: 2000
        })
      });

      if (!chatResponse.ok) {
        const errorText = await chatResponse.text();
        console.error(`❌ Chat Completions API error: ${chatResponse.status} - ${errorText}`);
        throw new Error(`OpenAI Chat Completions API error: ${chatResponse.status} - ${errorText}`);
      }

      const chatData = await chatResponse.json();
      const message = extractContent(chatData);
      
      if (!message) {
        throw new Error('No message content returned from Chat Completions API');
      }
      
      // Try to extract URLs from the response text
      const sources: string[] = [];
      const urlRegex = /https?:\/\/[^\s]+/g;
      const matches = message.match(urlRegex);
      if (matches) {
        sources.push(...matches.slice(0, 5));
      }

      console.log('✅ Fallback Chat Completions response generated');
      return { message, sources };
    } catch (fallbackError: any) {
      console.error('❌ Both Responses API and Chat Completions failed:', fallbackError);
      throw fallbackError;
    }
  }
}

// DOME ZONES: Helper functions for save command detection and classification

// Detect if message is a save command
function isSaveCommand(message: string): boolean {
  const normalized = message.toLowerCase().trim();
  
  // Remove common prefixes like "yes,", "okay,", "sure,", "yeah," etc.
  const cleaned = normalized.replace(/^(yes|okay|ok|sure|yeah|yep|alright|all right)[,\s]+/i, '').trim();
  
  // Simple save patterns: "save", "save that", "save this", "please save"
  const simpleSavePatterns = [
    "save",
    "save that",
    "save this",
    "please save",
    "save that for me",
    "save this for me",
    "please save that",
    "please save this"
  ];
  
  // Check cleaned version first (handles "yes, save that for me")
  for (const pattern of simpleSavePatterns) {
    if (cleaned === pattern || cleaned.startsWith(pattern + " ")) {
      return true;
    }
  }
  
  // Check original normalized version (handles direct "save" commands)
  for (const pattern of simpleSavePatterns) {
    if (normalized === pattern || normalized.startsWith(pattern + " ")) {
      return true;
    }
  }
  
  // More specific save triggers (existing patterns)
  const saveTriggers = [
    "ray, save this:",
    "save this:",
    "save this note:",
    "save this as a memory:",
    "save this task:",
    "save this reminder:",
    "save a pill reminder:",
    "save a workout:",
    "save to",
    "save this to"
  ];
  
  // Check if message starts with any trigger (case-insensitive, allow extra spaces)
  for (const trigger of saveTriggers) {
    const triggerLower = trigger.toLowerCase();
    // Remove leading "ray," if present for comparison
    const finalCleaned = cleaned.replace(/^ray,\s*/i, '').trim();
    if (finalCleaned.startsWith(triggerLower) || cleaned.startsWith(triggerLower) || normalized.startsWith(triggerLower)) {
      return true;
    }
  }
  
  return false;
}

// Find last assistant message from conversation history
// Returns the MOST RECENT assistant message (searches backwards from the end)
function findLastAssistantMessage(conversationHistory: any[]): string | null {
  if (!Array.isArray(conversationHistory)) {
    console.log('💾 findLastAssistantMessage: conversationHistory is not an array');
    return null;
  }
  
  console.log('💾 findLastAssistantMessage: searching through', conversationHistory.length, 'messages');
  
  // Search backwards through conversation history to find the MOST RECENT assistant message
  for (let i = conversationHistory.length - 1; i >= 0; i--) {
    const msg = conversationHistory[i];
    if (msg && typeof msg === 'object') {
      const role = msg.role;
      const content = msg.content;
      if (role === 'assistant' && content && typeof content === 'string' && content.trim().length > 0) {
        const trimmedContent = content.trim();
        console.log('💾 findLastAssistantMessage: found assistant message at index', i, 'length:', trimmedContent.length);
        console.log('💾 findLastAssistantMessage: preview:', trimmedContent.substring(0, 100));
        return trimmedContent;
      }
    }
  }
  
  console.log('💾 findLastAssistantMessage: no assistant message found');
  return null;
}

// Extract content from save command by stripping trigger phrase
function extractSaveContent(message: string): string {
  const normalized = message.trim();
  const saveTriggers = [
    "ray, save this:",
    "save this:",
    "save this note:",
    "save this as a memory:",
    "save this task:",
    "save this reminder:",
    "save a pill reminder:",
    "save a workout:",
    "save to",
    "save this to"
  ];
  
  // Remove leading "ray," if present
  let cleaned = normalized.replace(/^ray,\s*/i, '').trim();
  
  // Find and remove the trigger phrase
  for (const trigger of saveTriggers) {
    const triggerLower = trigger.toLowerCase();
    if (cleaned.toLowerCase().startsWith(triggerLower)) {
      cleaned = cleaned.substring(triggerLower.length).trim();
      break;
    }
  }
  
  // If nothing remains, use full original message
  return cleaned.length > 0 ? cleaned : normalized;
}

// Classify saved item into subzone within Brain
// NOTE: zone is ALWAYS 'brain' for ray_items table
function classifySavedItem(rawContent: string): {
  zone: string;
  subzone: string | null;
  kind: string;
} {
  const lowerContent = rawContent.toLowerCase();
  
  // Zone is ALWAYS 'brain' for ray_items table
  const zone = "brain";
  let subzone: string | null = "general";
  let kind = "note";
  
  // Food-related content (recipes, meal plans, flavor notes)
  const foodKeywords = ["recipe", "meal", "food", "taste", "flavor", "cooking", "ingredient", "dish", "cuisine", "catfish", "seafood", "breakfast", "lunch", "dinner", "snack"];
  const hasFoodKeywords = foodKeywords.some(keyword => lowerContent.includes(keyword));
  
  if (hasFoodKeywords) {
    subzone = "food";
    return { zone, subzone, kind };
  }
  
  // Research/explanations/how-to content
  const researchKeywords = ["how to", "explain", "what is", "why", "research", "study", "analysis", "guide", "tutorial", "walking plan", "plan", "steps"];
  const hasResearchKeywords = researchKeywords.some(keyword => lowerContent.includes(keyword));
  
  if (hasResearchKeywords) {
    subzone = "research";
    return { zone, subzone, kind };
  }
  
  // DomeAI project planning
  const projectKeywords = ["dome", "project", "idea", "feature", "roadmap", "architecture"];
  const hasProjectKeywords = projectKeywords.some(keyword => lowerContent.includes(keyword));
  
  if (hasProjectKeywords) {
    subzone = "projects";
    return { zone, subzone, kind };
  }
  
  // Family-related notes
  const familyKeywords = ["family", "spouse", "children", "kids", "birthday", "anniversary", "parent"];
  const hasFamilyKeywords = familyKeywords.some(keyword => lowerContent.includes(keyword));
  
  if (hasFamilyKeywords) {
    subzone = "family";
    return { zone, subzone, kind };
  }
  
  // Health research/information
  const healthKeywords = ["health", "medical", "doctor", "symptom", "condition", "treatment", "medicine", "wellness"];
  const hasHealthKeywords = healthKeywords.some(keyword => lowerContent.includes(keyword));
  
  if (hasHealthKeywords) {
    subzone = "health_research";
    return { zone, subzone, kind };
  }
  
  // Default: general subzone
  return { zone, subzone: "general", kind };
}

// Build title from content (max 60 chars)
function buildTitleFromContent(rawContent: string): string {
  const trimmed = rawContent.trim();
  if (trimmed.length <= 60) return trimmed;
  return trimmed.slice(0, 57) + "...";
}

// Map zone to pretty label with emoji
function getZoneLabel(zone: string): string {
  const zoneMap: Record<string, string> = {
    brain: "🧠 Dome Brain",
    nudges: "⏰ Nudges",
    calendar: "📅 Calendar",
    tasks: "✅ Tasks",
    exercise: "🏃 Exercise",
    meds: "💊 Meds",
    health: "🩺 Health"
  };
  return zoneMap[zone] || `📝 ${zone}`;
}

// SHORT CONTEXT BUILDER: Creates a sliding window of recent messages for OpenAI
// This prevents sending the entire conversation history and reduces token usage
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
// userProfile contains personal facts stored on-device (name, kids, birthdays, etc.)
function formatUserProfile(userProfile: string | undefined): string {
  if (!userProfile || userProfile.trim().length === 0) {
    return '';
  }
  
  return `\n\nUSER PROFILE (stable personal facts you always remember):\n${userProfile.trim()}\n\nThese facts persist across all conversations. Use them naturally when relevant, but don't repeat them unnecessarily.`;
}

// Helper function to extract new personal details from user message and Ray's response
// Returns structured JSON that iOS app can store on-device
async function extractPersonalDetails(userMessage: string, rayResponse: string, openaiApiKey: string, extractContentFn: (responseData: any) => string): Promise<any[]> {
  try {
    const extractionPrompt = `Analyze this conversation and extract any NEW personal facts about the user that should be remembered permanently.

User said: "${userMessage}"
Ray responded: "${rayResponse}"

Extract ONLY new personal facts such as:
- Name (if mentioned)
- Family members (spouse, children, parents, etc.)
- Important dates (birthdays, anniversaries, etc.)
- Personal preferences or important life details
- Significant life events

Return a JSON object with this exact format:
{
  "facts": [
    {
      "fact": "the personal fact to remember",
      "category": "personal" | "family" | "dates" | "preferences" | "events"
    }
  ]
}

If NO new personal facts are mentioned, return: {"facts": []}

Return ONLY valid JSON, no other text.`;

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
            content: 'You are a personal fact extraction system. Extract only new personal facts from conversations. Return valid JSON only.'
          },
          {
            role: 'user',
            content: extractionPrompt
          }
        ],
        temperature: 0.3,
        max_tokens: 500,
        response_format: { type: 'json_object' }
      })
    });

    if (!response.ok) {
      console.error('❌ Personal details extraction failed:', response.status);
      return [];
    }

    const data = await response.json();
    const content = extractContentFn(data);
    
    try {
      const parsed = JSON.parse(content);
      // Handle { "facts": [...] } format
      const facts = parsed.facts || [];
      return Array.isArray(facts) ? facts : [];
    } catch (e) {
      console.error('❌ Failed to parse extracted personal details:', e);
      return [];
    }
  } catch (error) {
    console.error('❌ Error extracting personal details:', error);
    return [];
  }
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
    const { query, conversationHistory, chatSessionId, userProfile, userEmail } = req.body;
    
    // Process userEmail: trim and validate
    const trimmedUserEmail = (userEmail || "").trim() || undefined;

    if (!query || typeof query !== 'string') {
      return res.status(400).json({ 
        error: 'Bad request', 
        message: 'Missing or invalid "query" field in request body' 
      });
    }

    const userQuery = query;
    const currentChatSessionId = chatSessionId || 'default'; // Default session if not provided
    
    console.log('📥 Request received - Query:', userQuery.substring(0, 100));
    console.log('📥 Chat Session ID:', currentChatSessionId);
    console.log('📥 User Profile provided:', userProfile ? 'Yes' : 'No');
    if (userProfile) {
      console.log('📥 User Profile preview:', userProfile.substring(0, 100) + '...');
    }

    // DOME ZONES: Check for save commands BEFORE OpenAI processing
    if (isSaveCommand(userQuery)) {
      console.log('💾 Save command detected:', userQuery.substring(0, 100));
      console.log('💾 conversationHistory length:', (conversationHistory || []).length);
      
      try {
        // Step 1: Find the MOST RECENT assistant message from conversation history
        // This should be the latest response Ray just gave to the user
        const lastAssistantMsg = findLastAssistantMessage(conversationHistory || []);
        
        if (!lastAssistantMsg) {
          console.error('❌ Save command detected but no assistant message found in conversation history');
          return res.status(200).json({
            ok: true,
            tier: 0,
            model: 'dome-zones',
            message: "I'd like to save that for you, but I don't see anything to save from our recent conversation. Could you ask me something first, then ask me to save my response?",
            reasoning: 'Save command detected but no assistant message found',
            sources: [],
            extractedPersonalDetails: undefined
          });
        }
        
        // Step 2: Use the last assistant message as content to save
        // This is the FULL text of the latest assistant answer
        const contentToSave = lastAssistantMsg;
        console.log('💾 Content to save (length):', contentToSave.length);
        console.log('💾 Content to save (preview):', contentToSave.substring(0, 200));
        
        // Step 3: Build title from first part of content (max 60 chars)
        // Alternatively, we could use the user's query, but using content preview is more descriptive
        const title = buildTitleFromContent(contentToSave);
        console.log('💾 Title:', title);
        
        // Step 4: Classify item (defaults to brain zone and note kind)
        const classification = classifySavedItem(contentToSave);
        console.log('💾 Classification:', classification);
        
        // Step 5: Insert directly into Supabase with ALL required fields
        // Ensure we're using the LATEST assistant message, not stale data
        // NOTE: zone is ALWAYS 'brain' for ray_items table
        const insertPayload = {
          title: title.trim(),
          content: contentToSave.trim(), // Full text of latest assistant answer
          zone: 'brain', // ALWAYS 'brain' for ray_items table
          subzone: classification.subzone || 'general',
          kind: classification.kind || 'note', // Default to 'note'
          source: 'assistant_answer', // Ray is saving his own answer
          last_ai_message: contentToSave.trim() // Same as content for now
        };
        
        // CRITICAL: Log the FULL payload being sent to Supabase
        console.log('💾 ===== SUPABASE INSERT ATTEMPT =====');
        console.log('💾 Insert payload (FULL):', JSON.stringify(insertPayload, null, 2));
        console.log('💾 Title:', insertPayload.title);
        console.log('💾 Content length:', insertPayload.content.length);
        console.log('💾 Content preview:', insertPayload.content.substring(0, 200));
        console.log('💾 Zone:', insertPayload.zone);
        console.log('💾 Subzone:', insertPayload.subzone);
        console.log('💾 Kind:', insertPayload.kind);
        console.log('💾 Source:', insertPayload.source);
        console.log('💾 Last AI message length:', insertPayload.last_ai_message.length);
        console.log('💾 ====================================');
        
        // CRITICAL: Await the insert and check for errors
        const { data, error } = await supabaseAdmin
          .from('ray_items')
          .insert(insertPayload)
          .select()
          .single();
        
        // CRITICAL: Only claim success if insert actually succeeded
        if (error) {
          console.error('❌ ===== SUPABASE INSERT FAILED =====');
          console.error('❌ Error code:', error.code);
          console.error('❌ Error message:', error.message);
          console.error('❌ Error details:', JSON.stringify(error, null, 2));
          console.error('❌ ====================================');
          return res.status(200).json({
            ok: true,
            tier: 0,
            model: 'dome-zones',
            message: "I tried to save that, but something went wrong. Please try again later.",
            reasoning: 'Save command detected but Supabase insert failed',
            sources: [],
            extractedPersonalDetails: undefined
          });
        }
        
        // CRITICAL: Verify we got data back before claiming success
        if (!data || !data.id) {
          console.error('❌ ===== SUPABASE INSERT RETURNED NO DATA =====');
          console.error('❌ Response data:', JSON.stringify(data, null, 2));
          console.error('❌ ====================================');
          return res.status(200).json({
            ok: true,
            tier: 0,
            model: 'dome-zones',
            message: "I tried to save that, but something went wrong. Please try again later.",
            reasoning: 'Save command detected but Supabase insert returned no data',
            sources: [],
            extractedPersonalDetails: undefined
          });
        }
        
        console.log('✅ ===== SUPABASE INSERT SUCCEEDED =====');
        console.log('✅ Item saved successfully to Supabase');
        console.log('✅ Saved item ID:', data.id);
        console.log('✅ Saved title:', data.title);
        console.log('✅ Saved content preview:', data.content?.substring(0, 100));
        console.log('✅ Saved zone:', data.zone);
        console.log('✅ ====================================');
        
        // Step 6: Return success message ONLY after confirmed successful insert
        // Build subzone label if available
        const subzoneLabels: Record<string, string> = {
          food: "Food & Meal Plans",
          research: "Research & Explanations",
          projects: "Projects & Ideas",
          family: "Family & Personal",
          health_research: "Health & Wellness",
          general: "Dome Brain"
        };
        const subzoneLabel = subzoneLabels[classification.subzone || 'general'] || 'Dome Brain';
        const successMessage = classification.subzone && classification.subzone !== 'general'
          ? `Got it — I've saved that in your Dome Brain under ${subzoneLabel}.`
          : `Got it — I've saved that in your Dome Brain.`;
        
        return res.status(200).json({
          ok: true,
          tier: 0,
          model: 'dome-zones',
          message: successMessage,
          reasoning: 'Save command processed successfully',
          sources: [],
          extractedPersonalDetails: undefined
        });
        
      } catch (error: any) {
        console.error('❌ Error processing save command:', error);
        return res.status(200).json({
          ok: true,
          tier: 0,
          model: 'dome-zones',
          message: "I tried to save that, but something went wrong. Please try again later.",
          reasoning: 'Save command detected but processing failed',
          sources: [],
          extractedPersonalDetails: undefined
        });
      }
    }

    // Prepare conversationHistory for sliding window processing
    // Extract only role and content fields (ignore chatSessionId and other metadata)
    // buildChatMessages will handle undefined/null, but we normalize it here for type safety
    const conversationHistoryArray: ChatMessage[] | undefined = Array.isArray(conversationHistory)
      ? conversationHistory.map(msg => ({
          role: msg.role as "user" | "assistant",
          content: msg.content
        }))
      : undefined;
    
    console.log('📥 Received conversationHistory length:', conversationHistoryArray?.length ?? 0);
    console.log('📥 Chat Session ID:', currentChatSessionId);
    console.log('📥 User Query:', userQuery.substring(0, 100));

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

TIER 3 (OpenAI Web Search + gpt-4o): Current events, news, live data, "today/recent/current/latest", population stats, weather, stocks, sports scores, "is X down", real-time information, recent happenings

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
    let extractedPersonalDetails: any[] = []; // New personal facts extracted from conversation
    
    // TIER 1: Simple queries with gpt-4o-mini (ALWAYS with web_search)
    if (tier === 1) {
      console.log('🤖 Tier 1: Using gpt-4o-mini with web_search');
      model = 'gpt-4o-mini';
      
      // Build system prompt with userProfile
      const userProfileSection = formatUserProfile(userProfile);
      const systemPrompt = `You are Ray, a helpful, reliable AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.${userProfileSection}

EMAIL CAPABILITY: Ray can send emails to the user via the backend when requested. If the user asks to "email that" or "send this to my email", the server logic will automatically send the assistant's reply by email. Ray should NOT say he cannot send emails; he should just respond normally, while the backend sends the email.

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

      const result = await answerUserQuestionWithWebSearch(
        userQuery,
        conversationHistoryArray,
        systemPrompt,
        openaiApiKey,
        'gpt-4o-mini'
      );
      
      message = result.message;
      sources = result.sources;
      console.log('✅ Tier 1 response generated with web_search');
    }
    // TIER 2: Complex queries with gpt-4o (ALWAYS with web_search)
    else if (tier === 2) {
      console.log('🤖 Tier 2: Using gpt-4o with web_search');
      model = 'gpt-4o';
      
      // Build system prompt with userProfile
      const tier2UserProfileSection = formatUserProfile(userProfile);
      const tier2SystemPrompt = `You are Ray, a helpful, reliable AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.

You excel at complex reasoning, coding, architecture, multi-step planning, and deep analysis. Provide thorough, well-reasoned responses.${tier2UserProfileSection}

EMAIL CAPABILITY: Ray can send emails to the user via the backend when requested. If the user asks to "email that" or "send this to my email", the server logic will automatically send the assistant's reply by email. Ray should NOT say he cannot send emails; he should just respond normally, while the backend sends the email.

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

      const result = await answerUserQuestionWithWebSearch(
        userQuery,
        conversationHistoryArray,
        tier2SystemPrompt,
        openaiApiKey,
        'gpt-4o'
      );
      
      message = result.message;
      sources = result.sources;
      console.log('✅ Tier 2 response generated with web_search');
    }
    // TIER 3: OpenAI Web Search + gpt-4o (ALWAYS with web_search)
    else if (tier === 3) {
      console.log('🔍 Tier 3: Using OpenAI Web Search + gpt-4o with web_search');
      model = 'openai-web-search';
      
      // Build system prompt with userProfile
      const tier3UserProfileSection = formatUserProfile(userProfile);
      const tier3SystemPrompt = `You are Ray, a helpful, reliable AI assistant living inside DomeAI. You help users organize their knowledge, tasks, and life using the Dome filing system.${tier3UserProfileSection}

You excel at answering questions about current events, news, live data, recent happenings, and real-time information.

EMAIL CAPABILITY: Ray can send emails to the user via the backend when requested. If the user asks to "email that" or "send this to my email", the server logic will automatically send the assistant's reply by email. Ray should NOT say he cannot send emails; he should just respond normally, while the backend sends the email.

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

You have access to the recent conversation history below (last ${MAX_HISTORY_MESSAGES} messages). Use it to maintain context.`;

      const result = await answerUserQuestionWithWebSearch(
        userQuery,
        conversationHistoryArray,
        tier3SystemPrompt,
        openaiApiKey,
        'gpt-4o'
      );
      
      message = result.message;
      sources = result.sources;
      console.log('✅ Tier 3 response generated with web_search');
      console.log('🔍 Web search sources:', sources.length);
    } else {
      // Invalid tier, default to Tier 1
      console.log('⚠️ Invalid tier, defaulting to Tier 1');
      return res.status(400).json({
        error: 'Invalid tier',
        message: `Tier ${tier} is not valid. Must be 1, 2, or 3.`
      });
    }

    // Extract new personal details from conversation (optional, non-blocking)
    // This runs after we have Ray's response, so it doesn't slow down the main flow
    try {
      extractedPersonalDetails = await extractPersonalDetails(userQuery, message, openaiApiKey, extractContent);
      if (extractedPersonalDetails.length > 0) {
        console.log('📝 Extracted personal details:', JSON.stringify(extractedPersonalDetails, null, 2));
      }
    } catch (extractError) {
      console.error('⚠️ Failed to extract personal details (non-critical):', extractError);
      // Don't fail the request if extraction fails
    }

    // Auto-send email if user requested it
    if (userRequestedEmail(userQuery)) {
      // Find the last assistant message (the one we're about to return)
      // This is the message variable that contains Ray's current response
      const lastAssistantMessage = message;
      
      // Create a subject from the first line or a generic title
      const firstLine = lastAssistantMessage.split('\n')[0];
      let emailSubject = "From Ray: Directions";
      if (firstLine && firstLine.length > 0) {
        const subjectPreview = firstLine.length > 50 
          ? firstLine.substring(0, 50) + '...' 
          : firstLine;
        emailSubject = `From Ray: ${subjectPreview}`;
      }
      
      // Convert message to HTML (preserve line breaks)
      const emailHtml = lastAssistantMessage.split('\n').map(line => {
        // Check if line starts with bullet points
        if (line.trim().startsWith('-') || line.trim().startsWith('•')) {
          return `<p style="margin: 8px 0;">${line.trim()}</p>`;
        }
        return `<p style="margin: 8px 0;">${line}</p>`;
      }).join('');
      
      const formattedHtml = `<div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333;">${emailHtml}</div>`;
      
      // Check if we have a user email
      if (!trimmedUserEmail) {
        // No email stored - modify Ray's response to be honest
        console.log('📧 Email requested but no userEmail provided');
        message = `I tried to email that, but I don't know your email address yet. Please open Dome's settings and add your email first. For now, here are the directions again:\n\n${lastAssistantMessage}`;
      } else {
        // We have an email - try to send it
        try {
          await sendRayEmail({
            to: trimmedUserEmail,
            subject: emailSubject,
            html: formattedHtml
          });
          
          console.log('📧 Auto-sent email:', {
            to: trimmedUserEmail,
            subject: emailSubject,
            triggerPhrase: userQuery,
            bodyPreview: lastAssistantMessage.substring(0, 100) + '...'
          });
          
          // Modify Ray's response to confirm email was sent
          message = `I've sent those directions to your email on file. Here's a quick recap of what I sent:\n\n${lastAssistantMessage}`;
        } catch (emailError: any) {
          // Email failed - modify Ray's response to be honest about the failure
          console.error('⚠️ Failed to send auto-email:', {
            error: emailError.message || 'Unknown error',
            triggerPhrase: userQuery,
            to: trimmedUserEmail
          });
          
          message = `I tried to email those directions to you, but something went wrong sending the email. For now, here's the full text so you can copy and paste it:\n\n${lastAssistantMessage}`;
        }
      }
    }

    // Return response
    // Note: Frontend manages conversation history - we don't need to save it here
    return res.status(200).json({
      ok: true,
      tier: tier,
      model: model,
      message: message,
      reasoning: reasoning,
      sources: sources,
      extractedPersonalDetails: extractedPersonalDetails.length > 0 ? extractedPersonalDetails : undefined
    });

  } catch (error: any) {
    console.error('❌ Error in /api/ray:', error);
    console.error('❌ Error stack:', error.stack);
    console.error('❌ Error details:', JSON.stringify(error, Object.getOwnPropertyNames(error)));
    return res.status(500).json({
      error: 'Internal server error',
      message: error.message || 'An unexpected error occurred',
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
}
