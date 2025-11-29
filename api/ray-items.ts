import type { VercelRequest, VercelResponse } from '@vercel/node';
import { supabaseAdmin } from './lib/supabaseAdmin';
import type { RayItem } from '../types/ray';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // Handle POST requests - create new ray_item
  if (req.method === 'POST') {
    try {
      const { title, content, zone, subzone, kind, tags } = req.body;

      // Validate input
      if (!title || typeof title !== 'string' || title.trim().length === 0) {
        return res.status(400).json({
          error: 'Bad request',
          message: 'Invalid or missing "title" field. Must be a non-empty string.'
        });
      }

      if (!content || typeof content !== 'string' || content.trim().length === 0) {
        return res.status(400).json({
          error: 'Bad request',
          message: 'Invalid or missing "content" field. Must be a non-empty string.'
        });
      }

      // Apply server-side defaults
      const finalZone = (zone && typeof zone === 'string' && zone.trim().length > 0) 
        ? zone.trim() 
        : 'brain';
      
      const finalKind = (kind && typeof kind === 'string' && kind.trim().length > 0) 
        ? kind.trim() 
        : 'note';
      
      const finalSubzone = (subzone && typeof subzone === 'string' && subzone.trim().length > 0) 
        ? subzone.trim() 
        : null;
      
      const finalTags = (tags && typeof tags === 'string' && tags.trim().length > 0) 
        ? tags.trim() 
        : null;

      // Insert into Supabase
      const { data, error } = await supabaseAdmin
        .from('ray_items')
        .insert({
          title: title.trim(),
          content: content.trim(),
          zone: finalZone,
          subzone: finalSubzone,
          kind: finalKind,
          tags: finalTags
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

      return res.status(200).json(data as RayItem);
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
