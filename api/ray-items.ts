import type { VercelRequest, VercelResponse } from '@vercel/node';
import { supabaseAdmin } from './lib/supabaseAdmin';
import type { RayItem } from '../types/ray';

// Map zone hint words to zone, subzone, and kind
function mapZoneHint(zoneHint: string | null | undefined): {
  zone: string;
  subzone: string | null;
  kind: string;
} {
  if (!zoneHint || typeof zoneHint !== 'string') {
    return { zone: 'brain', subzone: 'notes', kind: 'note' };
  }

  const hint = zoneHint.toLowerCase().trim();

  // Brain zone keywords
  if (['brain', 'note', 'notes', 'info', 'information'].some(kw => hint.includes(kw))) {
    return { zone: 'brain', subzone: 'notes', kind: 'note' };
  }

  // Nudges zone keywords
  if (['nudge', 'reminder', 'remind'].some(kw => hint.includes(kw))) {
    return { zone: 'nudges', subzone: null, kind: 'reminder' };
  }

  // Calendar zone keywords
  if (['calendar', 'appointment', 'event'].some(kw => hint.includes(kw))) {
    return { zone: 'calendar', subzone: null, kind: 'calendar_event' };
  }

  // Exercise zone keywords
  if (['exercise', 'workout', 'run', 'gym', 'walk'].some(kw => hint.includes(kw))) {
    return { zone: 'exercise', subzone: null, kind: 'log' };
  }

  // Meds zone keywords
  if (['med', 'meds', 'medication', 'pill'].some(kw => hint.includes(kw))) {
    return { zone: 'meds', subzone: null, kind: 'note' };
  }

  // Health zone keywords
  if (['health', 'doctor', 'blood pressure'].some(kw => hint.includes(kw))) {
    return { zone: 'health', subzone: null, kind: 'note' };
  }

  // Projects zone keywords
  if (['project', 'plan', 'idea'].some(kw => hint.includes(kw))) {
    return { zone: 'brain', subzone: 'projects', kind: 'note' };
  }

  // Default fallback
  return { zone: 'brain', subzone: 'notes', kind: 'note' };
}

// Detect if a message is a save command
function isSaveCommand(text: string): boolean {
  const normalized = text.toLowerCase().trim();
  const savePatterns = ['save', 'save that', 'save this'];
  return savePatterns.some(pattern => normalized === pattern || normalized.startsWith(pattern + ' '));
}

// Extract first 10-12 words for title
function extractTitleFromContent(content: string): string {
  const words = content.trim().split(/\s+/);
  const wordCount = Math.min(words.length, 12);
  const title = words.slice(0, wordCount).join(' ');
  return title + (words.length > wordCount ? '...' : '');
}

// Find last assistant message from conversation history
function findLastAssistantMessage(conversationHistory: any[]): string | null {
  if (!Array.isArray(conversationHistory)) {
    return null;
  }
  
  // Search backwards through conversation history
  for (let i = conversationHistory.length - 1; i >= 0; i--) {
    const msg = conversationHistory[i];
    if (msg && typeof msg === 'object') {
      const role = msg.role;
      const content = msg.content;
      if (role === 'assistant' && content && typeof content === 'string' && content.trim().length > 0) {
        return content.trim();
      }
    }
  }
  
  return null;
}

// Classify content based on title and content (fallback when no zoneHint)
function classifyContent(title: string, content: string): {
  zone: string;
  subzone: string | null;
  kind: string;
} {
  const lowerTitle = title.toLowerCase();
  const lowerContent = content.toLowerCase();
  const combined = `${lowerTitle} ${lowerContent}`;

  // Meds detection
  if (['pill', 'tablet', 'capsule', 'mg', 'dose', 'take'].some(kw => combined.includes(kw))) {
    const hasTime = ['every day at', 'at 8am', 'each morning', 'before bed'].some(kw => combined.includes(kw));
    return { zone: 'meds', subzone: null, kind: hasTime ? 'reminder' : 'note' };
  }

  // Reminder detection
  if (['remind me', 'nudge me', 'every day at', 'tomorrow at'].some(kw => combined.includes(kw))) {
    return { zone: 'nudges', subzone: null, kind: 'reminder' };
  }

  // Exercise detection
  if (['workout', 'ran', 'run', 'walked', 'steps', 'gym', 'lifting'].some(kw => combined.includes(kw))) {
    return { zone: 'exercise', subzone: null, kind: 'log' };
  }

  // Task detection (action verbs)
  if (['call ', 'email ', 'text ', 'buy ', 'pick up ', 'schedule '].some(kw => lowerContent.startsWith(kw))) {
    return { zone: 'tasks', subzone: 'personal', kind: 'task' };
  }

  // Calendar detection
  if (['on friday', 'at 7pm', 'on monday', 'next week', 'tomorrow'].some(kw => combined.includes(kw)) &&
      !combined.includes('remind me')) {
    return { zone: 'calendar', subzone: null, kind: 'calendar_event' };
  }

  // Default
  return { zone: 'brain', subzone: 'notes', kind: 'note' };
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Handle POST requests - create new ray_item
  if (req.method === 'POST') {
    try {
      const { title, content, zone, subzone, kind, tags, zoneHint, source, conversationHistory } = req.body;

      // Check if this is a save command - if so, extract last assistant message
      let finalTitle = title;
      let finalContent = content;
      let isSaveCommandDetected = false;

      if (title && typeof title === 'string' && isSaveCommand(title.trim())) {
        console.log('💾 Save command detected in title:', title);
        isSaveCommandDetected = true;
      } else if (content && typeof content === 'string' && isSaveCommand(content.trim())) {
        console.log('💾 Save command detected in content:', content);
        isSaveCommandDetected = true;
      }

      if (isSaveCommandDetected) {
        // Find last assistant message from conversation history
        const lastAssistantMsg = findLastAssistantMessage(conversationHistory || []);
        
        if (!lastAssistantMsg) {
          return res.status(400).json({
            error: 'Bad request',
            message: 'Save command detected but no assistant message found in conversation history.'
          });
        }

        // Extract title (first 10-12 words) and content (full message)
        finalTitle = extractTitleFromContent(lastAssistantMsg);
        finalContent = lastAssistantMsg;
        
        console.log('💾 Extracted from assistant message:');
        console.log('💾 Title:', finalTitle);
        console.log('💾 Content length:', finalContent.length);
      }

      // Validate input
      if (!finalTitle || typeof finalTitle !== 'string' || finalTitle.trim().length === 0) {
        return res.status(400).json({
          error: 'Bad request',
          message: 'Invalid or missing "title" field. Must be a non-empty string.'
        });
      }

      if (!finalContent || typeof finalContent !== 'string' || finalContent.trim().length === 0) {
        return res.status(400).json({
          error: 'Bad request',
          message: 'Invalid or missing "content" field. Must be a non-empty string.'
        });
      }

      // Validate source
      // If save command detected, always use 'user_note'
      const validSource = isSaveCommandDetected 
        ? 'user_note'
        : (source === 'assistant_answer' || source === 'user_note' ? source : 'user_note');

      // Determine zone, subzone, and kind
      let finalZone = 'brain';
      let finalSubzone: string | null = 'notes';
      let finalKind = 'note';

      if (isSaveCommandDetected) {
        // Use defaults for save command: zone="brain", subzone=null, kind="note"
        finalZone = 'brain';
        finalSubzone = null;
        finalKind = 'note';
      }
      // If explicit zone/kind provided, use those (highest priority)
      else if (zone && typeof zone === 'string' && zone.trim().length > 0) {
        finalZone = zone.trim();
        finalSubzone = (subzone !== undefined && subzone !== null && typeof subzone === 'string' && subzone.trim().length > 0)
          ? subzone.trim()
          : null;
        finalKind = (kind && typeof kind === 'string' && kind.trim().length > 0)
          ? kind.trim()
          : 'note';
      }
      // If zoneHint is provided, use it
      else if (zoneHint && typeof zoneHint === 'string' && zoneHint.trim().length > 0) {
        const mapped = mapZoneHint(zoneHint);
        finalZone = mapped.zone;
        finalSubzone = mapped.subzone;
        finalKind = mapped.kind;
      }
      // Otherwise, classify based on content
      else {
        const classified = classifyContent(finalTitle.trim(), finalContent.trim());
        finalZone = classified.zone;
        finalSubzone = classified.subzone;
        finalKind = classified.kind;
      }

      // Ensure defaults are set
      if (!finalZone) finalZone = 'brain';
      if (!finalKind) finalKind = 'note';
      if (finalSubzone === undefined) finalSubzone = isSaveCommandDetected ? null : 'notes';

      const finalTags = (tags && typeof tags === 'string' && tags.trim().length > 0)
        ? tags.trim()
        : null;

      // Insert into Supabase
      const { data, error } = await supabaseAdmin
        .from('ray_items')
        .insert({
          title: finalTitle.trim(),
          content: finalContent.trim(),
          zone: finalZone,
          subzone: finalSubzone,
          kind: finalKind,
          tags: finalTags,
          source: validSource
        })
        .select()
        .single();

      if (error) {
        console.error('❌ Supabase insert error:', error);
        return res.status(500).json({
          error: 'Database error',
          message: error.message || 'Failed to save item'
        });
      }

      // Return response with success indicator
      return res.status(200).json({
        success: true,
        id: data.id,
        zone: data.zone,
        subzone: data.subzone,
        kind: data.kind,
        ...data
      } as RayItem & { success: boolean });
    } catch (error: any) {
      console.error('❌ Error in POST /api/ray-items:', error);
      return res.status(500).json({
        error: 'Internal server error',
        message: error.message || 'An unexpected error occurred'
      });
    }
  }

  // Handle GET requests - list all ray_items
  if (req.method === 'GET') {
    try {
      const { zone, kind } = req.query;
      
      let query = supabaseAdmin
        .from('ray_items')
        .select('*');
      
      // Apply filters if provided
      if (zone && typeof zone === 'string') {
        query = query.eq('zone', zone);
      }
      
      if (kind && typeof kind === 'string') {
        query = query.eq('kind', kind);
      }
      
      const { data, error } = await query.order('created_at', { ascending: false });

      if (error) {
        console.error('❌ Supabase select error:', error);
        return res.status(500).json({
          error: 'Database error',
          message: error.message || 'Failed to fetch items'
        });
      }

      return res.status(200).json(data as RayItem[]);
    } catch (error: any) {
      console.error('❌ Error in GET /api/ray-items:', error);
      return res.status(500).json({
        error: 'Internal server error',
        message: error.message || 'An unexpected error occurred'
      });
    }
  }

  // Method not allowed
  return res.status(405).json({
    error: 'Method not allowed',
    message: 'Only GET and POST requests are accepted'
  });
}
