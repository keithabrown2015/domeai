/*
 * SQL ALTER TABLE Statement for Supabase
 * Run this in the Supabase SQL Editor to extend ray_items table for Dome Zones
 */

alter table public.ray_items
  add column if not exists zone text not null default 'brain',
  add column if not exists subzone text,
  add column if not exists kind text not null default 'note',
  add column if not exists tags text,
  add column if not exists source text not null default 'user_note';

