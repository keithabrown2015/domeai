import { NextRequest, NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  const appToken = request.headers.get('x-app-token');

  if (appToken !== process.env.APP_TOKEN) {
    console.log('❌ Unauthorized request to /api/google-search');
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { query, num } = body;

    if (!query) {
      return NextResponse.json({ error: 'Query is required' }, { status: 400 });
    }

    const apiKey = process.env.GOOGLE_API_KEY;
    const cx = process.env.GOOGLE_CX;

    if (!apiKey || !cx) {
      console.error('❌ Missing Google credentials');
      return NextResponse.json(
        { error: 'Server configuration error' },
        { status: 500 }
      );
    }

    const searchURL = `https://www.googleapis.com/customsearch/v1?key=${apiKey}&cx=${cx}&q=${encodeURIComponent(query)}&num=${num || 10}`;

    console.log('🔍 Google Search for:', query);
    const response = await fetch(searchURL);

    if (!response.ok) {
      const error = await response.text();
      console.error('❌ Google API error:', response.status, error);
      return NextResponse.json(
        { error: 'Google Search API error', details: error },
        { status: response.status }
      );
    }

    const data = await response.json();
    console.log('✅ Search success:', data.items?.length || 0, 'results');
    return NextResponse.json(data);
  } catch (error: any) {
    console.error('❌ Search relay error:', error.message);
    return NextResponse.json(
      { error: 'Internal server error', message: error.message },
      { status: 500 }
    );
  }
}

