import { NextRequest, NextResponse } from 'next/server';

export const runtime = 'edge';
export const dynamic = 'force-dynamic';

const GOOGLE_API_KEY = process.env.GOOGLE_API_KEY;
const GOOGLE_CX = process.env.GOOGLE_CX;
const APP_TOKEN = process.env.APP_TOKEN;

export async function POST(request: NextRequest) {
  console.log('🔍 /api/google-search called');

  if (!GOOGLE_API_KEY || !GOOGLE_CX) {
    console.error('❌ Missing Google Search environment variables');
    return NextResponse.json({ error: 'Server misconfiguration' }, { status: 500 });
  }

  const appToken = request.headers.get('X-App-Token');
  if (!appToken || appToken !== APP_TOKEN) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const { query, num } = await request.json();
    console.log('🔍 Searching for:', query);

    if (!query || typeof query !== 'string') {
      return NextResponse.json({ error: 'Query is required' }, { status: 400 });
    }

    const searchURL = new URL('https://www.googleapis.com/customsearch/v1');
    searchURL.searchParams.set('key', GOOGLE_API_KEY);
    searchURL.searchParams.set('cx', GOOGLE_CX);
    searchURL.searchParams.set('q', query);
    searchURL.searchParams.set('num', String(num || 10));

    const googleResponse = await fetch(searchURL.toString());

    if (!googleResponse.ok) {
      const errorText = await googleResponse.text();
      console.log('❌ Google Search API error:', errorText);
      return NextResponse.json(
        { error: 'Google Search API error', details: errorText },
        { status: googleResponse.status }
      );
    }

    const data = await googleResponse.json();
    console.log('✅ Google search success');
    return NextResponse.json(data);
  } catch (error: any) {
    console.error('❌ Search relay error:', error);
    return NextResponse.json(
      { error: 'Internal server error', message: error?.message ?? 'Unknown error' },
      { status: 500 }
    );
  }
}

