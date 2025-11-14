import { NextRequest, NextResponse } from 'next/server';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  const appToken = request.headers.get('x-app-token');

  if (appToken !== process.env.APP_TOKEN) {
    console.log('❌ Unauthorized request to /api/openai');
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const body = await request.json();
    const { messages, model, max_tokens, temperature } = body;

    console.log('🤖 OpenAI relay:', {
      messageCount: messages?.length,
      model: model || 'gpt-4o-mini',
    });

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${process.env.OPENAI_API_KEY}`,
      },
      body: JSON.stringify({
        model: model || 'gpt-4o-mini',
        messages,
        max_tokens: max_tokens || 1000,
        temperature: temperature || 0.7,
      }),
    });

    if (!response.ok) {
      const error = await response.text();
      console.error('❌ OpenAI API error:', response.status, error);
      return NextResponse.json(
        { error: 'OpenAI API error', details: error },
        { status: response.status }
      );
    }

    const data = await response.json();
    console.log('RAW OPENAI RESPONSE:', JSON.stringify(data, null, 2));
    console.log('✅ OpenAI success');
    return NextResponse.json(data);
  } catch (error: any) {
    console.error('❌ Relay error:', error.message);
    return NextResponse.json(
      { error: 'Internal server error', message: error.message },
      { status: 500 }
    );
  }
}

