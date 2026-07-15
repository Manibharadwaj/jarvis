// ── Agent loop: calls GLM (z.ai) with function calling, executes tools, returns response ─

// Env vars read lazily (ESM imports are hoisted before dotenv config runs)
function getGlmConfig() {
  return {
    baseUrl: process.env.GLM_BASE_URL || 'https://api.z.ai/api/paas/v4',
    apiKey:  process.env.GLM_API_KEY  || '',
    model:   process.env.GLM_MODEL    || 'glm-4.5-flash',
  };
}

const SIGNOFFS = [
  'goodbye', 'good night', 'good bye', 'happy morning',
  'i will call in four hours', 'i will wake you at 5 am',
  'have a productive day', 'have a good day', 'have a great day',
  'take care', 'see you', 'farewell',
];

function isSignoff(text) {
  const t = text.toLowerCase();
  return SIGNOFFS.some(s => t.includes(s));
}

function isTerminating(text) {
  const t = text.toLowerCase();
  return t.includes('terminating') && t.includes('access denied');
}

/**
 * Merge consecutive same-role messages and fix alternation.
 * Ollama requires strict system? -> user -> assistant -> user alternation.
 */
function mergeSameRoleMessages(messages) {
  if (messages.length <= 1) return messages;

  // Step 1: merge consecutive same-role messages
  const merged = [messages[0]];
  for (let i = 1; i < messages.length; i++) {
    const prev = merged[merged.length - 1];
    const curr = messages[i];
    if (curr.role === prev.role && curr.role !== 'tool') {
      // Merge content
      const prevContent = typeof prev.content === 'string' ? prev.content : JSON.stringify(prev.content);
      const currContent = typeof curr.content === 'string' ? curr.content : JSON.stringify(curr.content);
      prev.content = prevContent + '\n' + currContent;
    } else {
      merged.push(curr);
    }
  }

  // Step 2: absorb leading assistant messages into system prompt
  const result = [];
  let hasUser = false;
  for (const msg of merged) {
    if (msg.role === 'assistant' && !hasUser) {
      // No user message yet — fold into system
      const asstText = typeof msg.content === 'string' ? msg.content : JSON.stringify(msg.content);
      if (result.length > 0 && result[0].role === 'system') {
        const sysText = typeof result[0].content === 'string' ? result[0].content : JSON.stringify(result[0].content);
        result[0].content = sysText + '\n\n[Assistant already said]: ' + asstText;
      } else {
        result.unshift({ role: 'system', content: '[Assistant already said]: ' + asstText });
      }
    } else {
      if (msg.role === 'user') hasUser = true;
      result.push(msg);
    }
  }

  return result;
}

/**
 * Determine why a conversation ended.
 * Returns "completed", "access_denied", or "disconnected".
 */
function determineCallEnd(messages) {
  let identityFails = 0;
  let lastAssistantMsg = '';

  for (const msg of messages) {
    if (msg.role === 'assistant') {
      const content = typeof msg.content === 'string' ? msg.content : '';
      lastAssistantMsg = content;
      const lower = content.toLowerCase();
      if (lower.includes('access denied') && !lower.includes('terminating')) {
        identityFails++;
      }
    }
  }

  if (identityFails >= 3 || isTerminating(lastAssistantMsg)) return 'access_denied';
  if (isSignoff(lastAssistantMsg)) return 'completed';
  return 'disconnected';
}

/**
 * Run the agent loop: call Ollama with function calling, execute tools, loop until text response.
 * Returns { content, allMessages } where allMessages includes all new messages from this turn.
 */
async function runAgentLoop({ systemPrompt, messages, tools, pool, userId, maxIterations = 20 }) {
  const allMessages = []; // new messages generated during this loop
  const { baseUrl: GLM_BASE_URL, apiKey: GLM_API_KEY, model: GLM_MODEL } = getGlmConfig();

  let currentMessages = [
    { role: 'system', content: systemPrompt },
    ...messages,
  ];

  for (let i = 0; i < maxIterations; i++) {
    // Merge same-role messages before each call
    currentMessages = mergeSameRoleMessages(currentMessages);

    const body = {
      model: GLM_MODEL,
      messages: currentMessages,
      tools: tools.length > 0 ? tools : undefined,
      stream: false,
      thinking: { type: 'disabled' },
    };

    const headers = { 'Content-Type': 'application/json' };
    if (GLM_API_KEY) headers['Authorization'] = `Bearer ${GLM_API_KEY}`;

    let data;
    try {
      const resp = await fetch(`${GLM_BASE_URL}/chat/completions`, {
        method: 'POST',
        headers,
        body: JSON.stringify(body),
      });
      if (!resp.ok) {
        const errText = await resp.text();
        console.error(`[agent-loop] GLM error ${resp.status}: ${errText.slice(0, 200)}`);
        return { content: 'I encountered a system error. Please try again.', allMessages };
      }
      data = await resp.json();
    } catch (err) {
      console.error(`[agent-loop] Fetch error:`, err.message);
      return { content: 'Connection issue. Please try again shortly.', allMessages };
    }

    const choice = data.choices?.[0];
    if (!choice) {
      return { content: 'No response generated. Please try again.', allMessages };
    }

    const assistantMsg = choice.message;

    // If no tool calls, this is the final response
    if (!assistantMsg.tool_calls || assistantMsg.tool_calls.length === 0) {
      const content = assistantMsg.content || '';
      allMessages.push({ role: 'assistant', content });
      return { content, allMessages };
    }

    // Has tool calls — add assistant message with tool_calls, execute each, add tool results
    allMessages.push({
      role: 'assistant',
      content: assistantMsg.content || '',
      tool_calls: assistantMsg.tool_calls,
    });
    currentMessages.push({
      role: 'assistant',
      content: assistantMsg.content || '',
      tool_calls: assistantMsg.tool_calls,
    });

    for (const tc of assistantMsg.tool_calls) {
      const toolName = tc.function.name;
      let toolArgs;
      try {
        toolArgs = JSON.parse(tc.function.arguments || '{}');
      } catch {
        toolArgs = {};
      }

      console.log(`[agent-loop] Tool call: ${toolName}`, JSON.stringify(toolArgs));
      const { executeTool } = await import('./tools.js');
      const result = await executeTool(toolName, toolArgs, pool, userId);

      const toolResultMsg = {
        role: 'tool',
        tool_call_id: tc.id,
        content: String(result),
      };
      allMessages.push({ ...toolResultMsg, tool_name: toolName });
      currentMessages.push(toolResultMsg);
    }
  }

  return { content: 'Session limit reached. Goodbye.', allMessages };
}

export { runAgentLoop, mergeSameRoleMessages, determineCallEnd };