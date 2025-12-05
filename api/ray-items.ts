import type { VercelRequest, VercelResponse } from '@vercel/node';
import { supabaseAdmin } from './lib/supabaseAdmin';
import type { RayItem } from '../types/ray';

// Map zone hint words to subzone within Brain
// NOTE: zone is ALWAYS 'brain' for ray_items table
function mapZoneHint(zoneHint: string | null | undefined): {
  zone: string;
  subzone: string | null;
  kind: string;
} {
  // Zone is ALWAYS 'brain' for ray_items table
  const zone = 'brain';
  
  if (!zoneHint || typeof zoneHint !== 'string') {
    return { zone, subzone: 'general', kind: 'note' };
  }

  const hint = zoneHint.toLowerCase().trim();

  // Food-related keywords
  if (['food', 'recipe', 'meal', 'cooking'].some(kw => hint.includes(kw))) {
    return { zone, subzone: 'food', kind: 'note' };
  }

  // Research keywords
  if (['research', 'info', 'information', 'explain', 'how'].some(kw => hint.includes(kw))) {
    return { zone, subzone: 'research', kind: 'note' };
  }

  // Projects keywords
  if (['project', 'plan', 'idea', 'brain'].some(kw => hint.includes(kw))) {
    return { zone, subzone: 'projects', kind: 'note' };
  }

  // Family keywords
  if (['family', 'personal'].some(kw => hint.includes(kw))) {
    return { zone, subzone: 'family', kind: 'note' };
  }

  // Health keywords
  if (['health', 'doctor', 'medical'].some(kw => hint.includes(kw))) {
    return { zone, subzone: 'health_research', kind: 'note' };
  }

  // Default fallback
  return { zone, subzone: 'general', kind: 'note' };
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

// Classify content into subzone within Brain
// NOTE: zone is ALWAYS 'brain' for ray_items table
function classifyContent(title: string, content: string): {
  zone: string;
  subzone: string | null;
  kind: string;
} {
  const zone = 'brain';
  const lowerTitle = title.toLowerCase();
  const lowerContent = content.toLowerCase();
  const combined = `${lowerTitle} ${lowerContent}`;

  // Food-related content
  const foodKeywords = ['recipe', 'meal', 'food', 'taste', 'flavor', 'cooking', 'ingredient', 'dish', 'cuisine'];
  if (foodKeywords.some(kw => combined.includes(kw))) {
    return { zone, subzone: 'food', kind: 'note' };
  }

  // Research/explanations
  const researchKeywords = ['how to', 'explain', 'what is', 'why', 'research', 'study', 'analysis', 'guide', 'tutorial', 'plan', 'steps'];
  if (researchKeywords.some(kw => combined.includes(kw))) {
    return { zone, subzone: 'research', kind: 'note' };
  }

  // Projects
  const projectKeywords = ['dome', 'project', 'idea', 'feature', 'roadmap'];
  if (projectKeywords.some(kw => combined.includes(kw))) {
    return { zone, subzone: 'projects', kind: 'note' };
  }

  // Family
  const familyKeywords = ['family', 'spouse', 'children', 'kids', 'birthday', 'anniversary'];
  if (familyKeywords.some(kw => combined.includes(kw))) {
    return { zone, subzone: 'family', kind: 'note' };
  }

  // Health research
  const healthKeywords = ['health', 'medical', 'doctor', 'symptom', 'condition', 'treatment', 'wellness'];
  if (healthKeywords.some(kw => combined.includes(kw))) {
    return { zone, subzone: 'health_research', kind: 'note' };
  }

  // Default
  return { zone, subzone: 'general', kind: 'note' };
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
      // NOTE: zone is ALWAYS 'brain' for ray_items table
      const finalZone = 'brain';
      let finalSubzone: string | null = 'general';
      let finalKind = 'note';

      if (isSaveCommandDetected) {
        // Classify into subzone based on content
        const classified = classifyContent(finalTitle.trim(), finalContent.trim());
        finalSubzone = classified.subzone || 'general';
        finalKind = classified.kind || 'note';
      }
      // If explicit subzone/kind provided, use those (but zone is always 'brain')
      else if (subzone && typeof subzone === 'string' && subzone.trim().length > 0) {
        finalSubzone = subzone.trim();
        finalKind = (kind && typeof kind === 'string' && kind.trim().length > 0)
          ? kind.trim()
          : 'note';
      }
      // If zoneHint is provided, use it to determine subzone
      else if (zoneHint && typeof zoneHint === 'string' && zoneHint.trim().length > 0) {
        const mapped = mapZoneHint(zoneHint);
        finalSubzone = mapped.subzone || 'general';
        finalKind = mapped.kind || 'note';
      }
      // Otherwise, classify based on content
      else {
        const classified = classifyContent(finalTitle.trim(), finalContent.trim());
        finalSubzone = classified.subzone || 'general';
        finalKind = classified.kind || 'note';
      }

      // Ensure defaults are set
      if (!finalSubzone) finalSubzone = 'general';
      if (!finalKind) finalKind = 'note';

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
  // NOTE: ray_items table is Brain-only, so we always filter by zone='brain'
  if (req.method === 'GET') {
    try {
      const { subzone, kind } = req.query;
      
      let query = supabaseAdmin
        .from('ray_items')
        .select('*')
        .eq('zone', 'brain'); // Always filter by zone='brain'
      
      // Apply subzone filter if provided
      if (subzone && typeof subzone === 'string') {
        query = query.eq('subzone', subzone);
      }
      
      // Apply kind filter if provided
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
