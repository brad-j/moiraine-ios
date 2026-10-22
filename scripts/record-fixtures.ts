// `node scripts/record-fixtures.ts [name]`: records a conversation's event stream from the faux gaidin that
// scripts/dev-faux.ts runs, for MoiraineCore's tests. It opens the default agent's home stream, sends a few messages
// that make the faux model answer, call a tool that asks first, and ask a question, settles each request, then opens
// the stream again for the snapshot gaidin has at the end. Writes fixtures/<name>.sse (the stream as it came) and
// fixtures/<name>.final.json (the last snapshot), with the server's temp directory taken out.
//
// Start the server with FAUX_TOKENS_PER_SECOND set for answers that stream in as deltas.
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";

const base = process.env.GAIDIN_URL ?? "http://127.0.0.1:8420";
const name = process.argv[2] ?? "home";
const out = resolve(import.meta.dirname, "../fixtures");

const sleep = (ms: number) => new Promise((done) => setTimeout(done, ms));
async function post(path: string, body: unknown) {
	const response = await fetch(base + path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
	if (!response.ok) throw new Error(`${path}: ${response.status} ${await response.text()}`);
	return response.json();
}
async function get(path: string) {
	return (await fetch(base + path)).json();
}
/** Waits until the home conversation isn't running, after giving a run time to start. */
async function settled() {
	await sleep(300);
	for (let i = 0; i < 200; i++) {
		const activity = (await get("/api/agents/activity")) as { running: boolean }[];
		if (!activity.some((a) => a.running)) return;
		await sleep(100);
	}
	throw new Error("The run didn't end.");
}
async function waiting(): Promise<{ id: string; kind?: string }> {
	for (let i = 0; i < 100; i++) {
		const [first] = (await get("/api/approvals")) as { id: string; kind?: string }[];
		if (first !== undefined) return first;
		await sleep(100);
	}
	throw new Error("Nothing came to approve.");
}

/** The stream's text until `stop` aborts it. */
async function record(stop: AbortSignal): Promise<string> {
	const response = await fetch(`${base}/events?agent=gaidin`, { signal: stop });
	const reader = response.body!.getReader();
	const decoder = new TextDecoder();
	let text = "";
	try {
		for (;;) {
			const { done, value } = await reader.read();
			if (done) break;
			text += decoder.decode(value, { stream: true });
		}
	} catch (error) {
		if (!stop.aborted) throw error;
	}
	return text;
}

const scrub = (text: string) => text.replace(/\/(?:private\/)?var\/folders\/[^"]*?\/gaidin-e2e-[A-Za-z0-9]+/g, "/tmp/gaidin-e2e").replace(/\/tmp\/gaidin-e2e-[A-Za-z0-9]+/g, "/tmp/gaidin-e2e");

const abort = new AbortController();
const recording = record(abort.signal);
await sleep(500);
await post("/api/message", { content: "hello", agent: "gaidin" });
await settled();
await post("/api/message", { content: "markdown, please", agent: "gaidin" });
await settled();
await post("/api/message", { content: "fetch the page", agent: "gaidin" });
await post("/api/approvals/decide", { id: (await waiting()).id, decision: "once" });
await settled();
await post("/api/message", { content: "ask me something", agent: "gaidin" });
await post("/api/approvals/answer", { id: (await waiting()).id, answer: "Yes" });
await settled();
await sleep(500);
abort.abort();
const stream = await recording;

// A second connection starts with gaidin's own snapshot, which the reducer has to arrive at from the stream.
const again = new AbortController();
const final = record(again.signal);
await sleep(800);
again.abort();
const snapshot = (await final).split("\n").find((line) => line.startsWith("data: "))!.slice("data: ".length);

writeFileSync(resolve(out, `${name}.sse`), scrub(stream));
writeFileSync(resolve(out, `${name}.final.json`), `${scrub(snapshot)}\n`);
console.log(`wrote fixtures/${name}.sse and fixtures/${name}.final.json`);
