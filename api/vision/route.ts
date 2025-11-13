import { NextRequest, NextResponse } from 'next/server';

export const runtime = 'edge';
export const dynamic = 'force-dynamic';

const OPENAI_API_KEY = process.env.OPENAI_API_KEY;
const APP_TOKEN = process.env.APP_TOKEN;

export async function POST(request: NextRequest) {
  console.log('👁️ /api/vision called');

  if (!OPENAI_API_KEY) {
    console.error('❌ Missing OPENAI_API_KEY environment variable');
    return NextResponse.json({ error: 'Server misconfiguration' }, { status: 500 });
  }

  const appToken = request.headers.get('X-App-Token');
  if (!appToken || appToken !== APP_TOKEN) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  try {
    const { base64Image, prompt, max_tokens } = await request.json();

    const visionRequest = {
      model: 'gpt-4o',
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: prompt },
            {
              type: 'image_url',
              image_url: { url: `data:image/jpeg;base64,${base64Image}` },
            },
          ],
        },
      ],
      max_tokens: max_tokens || 1000,
    };

    const openAIResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${OPENAI_API_KEY}`,
      },
      body: JSON.stringify(visionRequest),
    });

    if (!openAIResponse.ok) {
      const errorText = await openAIResponse.text();
      console.log('❌ Vision API error:', errorText);
      return NextResponse.json(
        { error: 'Vision API error', details: errorText },
        { status: openAIResponse.status }
      );
    }

    const data = await openAIResponse.json();
    console.log('✅ Vision analysis complete');
    return NextResponse.json(data);
  } catch (error: any) {
    console.error('❌ Vision error:', error);
    return NextResponse.json(
      { error: 'Vision error', message: error?.message ?? 'Unknown error' },
      { status: 500 }
    );
  }
}

