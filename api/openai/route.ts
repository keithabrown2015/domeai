import { NextRequest, NextResponse } from 'next/server';

export const runtime = 'edge';
export const dynamic = 'force-dynamic';

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const APP_TOKEN = process.env.APP_TOKEN;

export async function POST(request: NextRequest) {
  console.log('📨 /api/openai called');

  if (!OPENAI_API_KEY) {
    console.error('❌ Missing OPENAI_API_KEY environment variable');
    return NextResponse.json({ error: 'Server misconfiguration' }, { status: 500 });
  }

  const appToken = request.headers.get('X-App-Token');
  if (!appToken || appToken !== APP_TOKEN) {
    console.log('❌ Invalid app token');
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const body = await request.json();
    console.log('📝 Request:', JSON.stringify(body).substring(0, 200));

    const openAIResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify(body),
    });

    if (!openAIResponse.ok) {
      const errorText = await openAIResponse.text();
      console.log('❌ OpenAI error:', errorText);
      return NextResponse.json(
        { error: 'OpenAI API error', details: errorText },
        { status: openAIResponse.status }
      );
    }

    const data = await openAIResponse.json();
    console.log('✅ OpenAI success');
    return NextResponse.json(data);
  } catch (error: any) {
    console.error('❌ Server error:', error);
    return NextResponse.json(
      { error: 'Server error', message: error?.message ?? 'Unknown error' },
      { status: 500 }
    );
  }
}

