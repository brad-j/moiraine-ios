// `node scripts/dev-faux.ts`: gaidin's e2e server from the checkout beside this one (a scripted model, no keys, a
// fresh data directory, removed when it stops), behind a proxy on 127.0.0.1:8420 that adds Tailscale-User-Login, as
// `tailscale serve` does on the tailnet. The simulator's app talks to http://127.0.0.1:8420. See gaidin's
// e2e/server.ts for what the model does with each message.
//
// On macOS there's no bubblewrap, so scripts/stub-bwrap goes first on gaidin's PATH: it runs nothing, and the faux
// model never makes a shell call.
import { spawn } from "node:child_process";
import { createServer, request } from "node:http";
import { resolve } from "node:path";
import { createInterface } from "node:readline";

/** The tailnet login the e2e server lets in. */
const USER = "brad@example.com";
const PORT = Number(process.env.PORT) || 8420;
const gaidinDir = resolve(import.meta.dirname, process.env.GAIDIN_DIR ?? "../../gaidin");

const child = spawn(process.execPath, ["--no-warnings", "e2e/server.ts", USER], {
	cwd: gaidinDir,
	stdio: ["ignore", "pipe", "inherit"],
	env: { ...process.env, PATH: `${resolve(import.meta.dirname, "stub-bwrap")}:${process.env.PATH ?? ""}` },
});
const upstream = await new Promise<number>((done, fail) => {
	child.once("exit", (code) => fail(new Error(`gaidin's e2e/server.ts exited with ${code}`)));
	createInterface({ input: child.stdout! }).on("line", (line) => {
		const match = /^port (\d+)$/.exec(line);
		if (match !== null) done(Number(match[1]));
		else console.log(`[gaidin] ${line}`);
	});
});

const proxy = createServer((incoming, outgoing) => {
	const headers = { ...incoming.headers, "tailscale-user-login": USER, host: `127.0.0.1:${upstream}` };
	const forwarded = request({ host: "127.0.0.1", port: upstream, method: incoming.method, path: incoming.url, headers }, (answer) => {
		outgoing.writeHead(answer.statusCode ?? 502, answer.headers);
		answer.pipe(outgoing);
	});
	forwarded.on("error", (error) => {
		if (!outgoing.headersSent) outgoing.writeHead(502, { "Content-Type": "text/plain" });
		outgoing.end(`gaidin: ${error.message}`);
	});
	incoming.pipe(forwarded);
	// An event stream the app closes closes gaidin's too.
	outgoing.on("close", () => forwarded.destroy());
});
proxy.listen(PORT, "127.0.0.1", () => console.log(`gaidin (faux) at http://127.0.0.1:${PORT}`));

const stop = () => {
	proxy.close();
	child.kill("SIGTERM");
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
child.once("exit", () => process.exit(0));
