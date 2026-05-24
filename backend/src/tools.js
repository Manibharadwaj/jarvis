// ── Tool definitions (OpenAI function-calling format) and executors ────────────
// Ported from agent.py @function_tool decorators

const TOOL_DEFS = {
  add_task: {
    type: 'function',
    function: {
      name: 'add_task',
      description: "Add a new task to today's schedule. Use this when the user wants to add a task.",
      parameters: {
        type: 'object',
        properties: {
          title: { type: 'string', description: "The task title, e.g. 'Gym session' or 'Review pull requests'" },
          time_slot: { type: 'string', description: "Optional time like '6:00 AM' or '2:00 PM'", nullable: true },
          category: { type: 'string', description: 'One of: work, code, gym, food, books, personal, other', default: 'other' },
        },
        required: ['title'],
      },
    },
  },
  mark_task_done: {
    type: 'function',
    function: {
      name: 'mark_task_done',
      description: 'Mark a task as completed. Use when the user confirms they finished a task.',
      parameters: {
        type: 'object',
        properties: {
          task_title: { type: 'string', description: 'The exact or partial title of the task to mark done' },
        },
        required: ['task_title'],
      },
    },
  },
  remove_task: {
    type: 'function',
    function: {
      name: 'remove_task',
      description: "Remove a task from today's schedule. Use when the user wants to delete/cancel a task.",
      parameters: {
        type: 'object',
        properties: {
          task_title: { type: 'string', description: 'The exact or partial title of the task to remove' },
        },
        required: ['task_title'],
      },
    },
  },
  reschedule_task: {
    type: 'function',
    function: {
      name: 'reschedule_task',
      description: 'Reschedule a task to a different time. Use when the user wants to move a task.',
      parameters: {
        type: 'object',
        properties: {
          task_title: { type: 'string', description: 'The exact or partial title of the task to reschedule' },
          new_time: { type: 'string', description: "The new time slot, e.g. '3:00 PM'" },
        },
        required: ['task_title', 'new_time'],
      },
    },
  },
  update_daily_log: {
    type: 'function',
    function: {
      name: 'update_daily_log',
      description: "Update a field in today's daily log. Use for tracking 5 pillars data.",
      parameters: {
        type: 'object',
        properties: {
          field: {
            type: 'string',
            description: 'One of: food_calories, food_target, food_notes, gym_done, gym_protein, gym_creatine, code_done, code_notes, office_in_time, office_out_time, books_title, books_pages, books_insights, day_score, day_notes, hydration_glasses',
          },
          value: {
            type: 'string',
            description: 'The value to set (e.g. "2500" for calories, "true" for gym_done)',
          },
        },
        required: ['field', 'value'],
      },
    },
  },
  log_calories: {
    type: 'function',
    function: {
      name: 'log_calories',
      description: 'Log food calories. When the user describes what they ate, estimate the total calories and save to the daily log. This ADDS to any existing calorie count.',
      parameters: {
        type: 'object',
        properties: {
          food_description: { type: 'string', description: "What they ate, e.g. '2 chapati with dal and rice'" },
          estimated_calories: { type: 'integer', description: 'Your best estimate of total calories for this meal/snack' },
        },
        required: ['food_description', 'estimated_calories'],
      },
    },
  },
};

// ── Tool executors (direct SQL via pool, matching agent.py tool logic) ───────

async function executeAddTask(args, pool, userId) {
  const { title, time_slot, category } = args;
  const validCats = ['work', 'code', 'gym', 'food', 'books', 'personal', 'other'];
  const cat = validCats.includes(category) ? category : 'other';
  const today = "(NOW() AT TIME ZONE 'Asia/Kolkata')::date";
  await pool.query(
    `INSERT INTO public.master_schedule (user_id, date, title, time_slot, category)
     VALUES ($1, ${today}, $2, $3, $4)`,
    [userId, title, time_slot || null, cat],
  );
  return `Task added: '${title}'${time_slot ? ` at ${time_slot}` : ''}`;
}

async function executeMarkTaskDone(args, pool, userId) {
  const { task_title } = args;
  const today = "(NOW() AT TIME ZONE 'Asia/Kolkata')::date";
  const { rows } = await pool.query(
    `SELECT id, title FROM public.master_schedule
     WHERE user_id = $1 AND date = ${today} AND (done IS NOT TRUE) AND LOWER(title) LIKE LOWER($2)`,
    [userId, `%${task_title}%`],
  );
  if (rows.length === 0) return `Couldn't find a pending task matching '${task_title}'.`;
  const task = rows[0];
  await pool.query('UPDATE public.master_schedule SET done = true WHERE id = $1', [task.id]);
  return `Marked '${task.title}' as done.`;
}

async function executeRemoveTask(args, pool, userId) {
  const { task_title } = args;
  const today = "(NOW() AT TIME ZONE 'Asia/Kolkata')::date";
  const { rows } = await pool.query(
    `SELECT id, title FROM public.master_schedule
     WHERE user_id = $1 AND date = ${today} AND LOWER(title) LIKE LOWER($2)`,
    [userId, `%${task_title}%`],
  );
  if (rows.length === 0) return `Couldn't find a task matching '${task_title}'.`;
  const task = rows[0];
  await pool.query('DELETE FROM public.master_schedule WHERE id = $1', [task.id]);
  return `Removed '${task.title}' from your schedule.`;
}

async function executeRescheduleTask(args, pool, userId) {
  const { task_title, new_time } = args;
  const today = "(NOW() AT TIME ZONE 'Asia/Kolkata')::date";
  const { rows } = await pool.query(
    `SELECT id, title FROM public.master_schedule
     WHERE user_id = $1 AND date = ${today} AND LOWER(title) LIKE LOWER($2)`,
    [userId, `%${task_title}%`],
  );
  if (rows.length === 0) return `Couldn't find a task matching '${task_title}'.`;
  const task = rows[0];
  await pool.query('UPDATE public.master_schedule SET time_slot = $1 WHERE id = $2', [new_time, task.id]);
  return `Rescheduled '${task.title}' to ${new_time}.`;
}

const ALLOWED_DAILY_LOG_FIELDS = [
  'food_calories', 'food_target', 'food_notes',
  'gym_done', 'gym_protein', 'gym_creatine',
  'code_done', 'code_notes',
  'office_in_time', 'office_out_time',
  'books_title', 'books_pages', 'books_insights',
  'day_score', 'day_notes', 'hydration_glasses',
];

async function executeUpdateDailyLog(args, pool, userId) {
  const { field, value } = args;
  if (!ALLOWED_DAILY_LOG_FIELDS.includes(field)) {
    return `Invalid field: ${field}. Must be one of: ${ALLOWED_DAILY_LOG_FIELDS.join(', ')}`;
  }
  let parsed = value;
  if (['gym_done', 'gym_protein', 'gym_creatine', 'code_done'].includes(field)) {
    parsed = ['true', 'yes', '1', 'done'].includes(String(value).toLowerCase());
  } else if (['food_calories', 'food_target', 'books_pages', 'day_score', 'hydration_glasses'].includes(field)) {
    parsed = parseInt(value) || null;
  }
  const today = "(NOW() AT TIME ZONE 'Asia/Kolkata')::date";
  await pool.query(
    `INSERT INTO public.daily_log (user_id, date, ${field})
     VALUES ($1, ${today}, $2)
     ON CONFLICT (user_id, date) DO UPDATE SET ${field} = $2, updated_at = NOW()`,
    [userId, parsed],
  );
  return `Updated ${field} to ${value}.`;
}

async function executeLogCalories(args, pool, userId) {
  const { food_description, estimated_calories } = args;
  const today = "(NOW() AT TIME ZONE 'Asia/Kolkata')::date";

  // Get current calorie count
  const { rows } = await pool.query(
    `SELECT food_calories, food_notes FROM public.daily_log WHERE user_id = $1 AND date = ${today}`,
    [userId],
  );
  const current = rows[0] || {};
  const currentCal = current.food_calories || 0;
  const newTotal = currentCal + estimated_calories;

  const existingNotes = current.food_notes || '';
  const newNote = `${food_description} (~${estimated_calories} cal)`;
  const updatedNotes = existingNotes ? `${existingNotes}; ${newNote}` : newNote;

  // Upsert calories
  await pool.query(
    `INSERT INTO public.daily_log (user_id, date, food_calories)
     VALUES ($1, ${today}, $2)
     ON CONFLICT (user_id, date) DO UPDATE SET food_calories = $2, updated_at = NOW()`,
    [userId, newTotal],
  );
  // Upsert notes
  await pool.query(
    `INSERT INTO public.daily_log (user_id, date, food_notes)
     VALUES ($1, ${today}, $2)
     ON CONFLICT (user_id, date) DO UPDATE SET food_notes = $2, updated_at = NOW()`,
    [userId, updatedNotes],
  );

  return `Logged: ${food_description} (~${estimated_calories} cal). Running total: ${newTotal} cal.`;
}

const EXECUTORS = {
  add_task: executeAddTask,
  mark_task_done: executeMarkTaskDone,
  remove_task: executeRemoveTask,
  reschedule_task: executeRescheduleTask,
  update_daily_log: executeUpdateDailyLog,
  log_calories: executeLogCalories,
};

async function executeTool(name, args, pool, userId) {
  const fn = EXECUTORS[name];
  if (!fn) return `Unknown tool: ${name}`;
  try {
    return await fn(args, pool, userId);
  } catch (err) {
    console.error(`[tool] ${name} error:`, err.message);
    return `Tool error: ${err.message}`;
  }
}

// ── Per-call-type tool subsets (matching agent.py agent classes) ──────────────

const TOOLS_BY_CALL_TYPE = {
  wakeup: ['add_task', 'mark_task_done', 'remove_task', 'reschedule_task'],
  'checkin-morning': ['mark_task_done', 'update_daily_log', 'log_calories', 'remove_task', 'reschedule_task'],
  'checkin-midday': ['mark_task_done', 'reschedule_task', 'remove_task', 'add_task'],
  'checkin-afternoon': ['mark_task_done', 'update_daily_log', 'log_calories', 'reschedule_task', 'remove_task'],
  evening: ['mark_task_done', 'update_daily_log', 'log_calories', 'remove_task', 'reschedule_task'],
  night: ['mark_task_done', 'update_daily_log', 'log_calories', 'remove_task', 'reschedule_task'],
  jarvis: ['add_task', 'mark_task_done', 'remove_task', 'reschedule_task', 'update_daily_log', 'log_calories'],
  manual: ['add_task', 'mark_task_done', 'remove_task', 'reschedule_task', 'update_daily_log', 'log_calories'],
};

function getToolsForCallType(callType) {
  const names = TOOLS_BY_CALL_TYPE[callType] || TOOLS_BY_CALL_TYPE.jarvis;
  return names.map(n => TOOL_DEFS[n]).filter(Boolean);
}

export { TOOL_DEFS, executeTool, getToolsForCallType, ALLOWED_DAILY_LOG_FIELDS };