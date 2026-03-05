import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execSync } from "child_process";
import { writeFileSync, unlinkSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

function run(cmd: string, cwd?: string): string {
  try {
    return execSync(cmd, {
      encoding: "utf-8",
      cwd,
      timeout: 30000,
    }).trim();
  } catch (e: unknown) {
    const err = e as { stderr?: string; message?: string };
    throw new Error(err.stderr || err.message || "Command failed");
  }
}

function writeModuleContent(name: string, content: string): void {
  const repoPath = run("ai-inst repo path");
  const modulePath = join(repoPath, "modules", `${name}.md`);
  writeFileSync(modulePath, content, "utf-8");
}

const server = new McpServer({
  name: "ai-inst",
  version: "0.1.0",
});

// ─── Tools ───────────────────────────────────────────────────────────────────

server.tool("list_modules", "List all available instruction modules", {}, async () => {
  const output = run("ai-inst list");
  return { content: [{ type: "text", text: output || "No modules found." }] };
});

server.tool(
  "read_module",
  "Read the content of a module",
  { name: z.string().describe("Module name") },
  async ({ name }) => {
    const output = run(`ai-inst show ${name}`);
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "create_module",
  "Create a new instruction module",
  {
    name: z.string().describe("Module name"),
    content: z.string().describe("Module content (markdown)"),
  },
  async ({ name, content }) => {
    const repoPath = run("ai-inst repo path");
    const modulePath = join(repoPath, "modules", `${name}.md`);
    writeFileSync(modulePath, content, "utf-8");
    run(`cd "${repoPath}" && git add -A && git commit -m "add module: ${name}"`);
    return { content: [{ type: "text", text: `Module '${name}' created.` }] };
  }
);

server.tool(
  "update_module",
  "Update the content of an existing module",
  {
    name: z.string().describe("Module name"),
    content: z.string().describe("New module content (markdown)"),
  },
  async ({ name, content }) => {
    // Verify it exists
    run(`ai-inst show ${name}`);
    writeModuleContent(name, content);
    const repoPath = run("ai-inst repo path");
    run(`cd "${repoPath}" && git add -A && git commit -m "update module: ${name}"`);
    return { content: [{ type: "text", text: `Module '${name}' updated.` }] };
  }
);

server.tool(
  "delete_module",
  "Delete a module",
  { name: z.string().describe("Module name") },
  async ({ name }) => {
    run(`ai-inst rm ${name}`);
    return { content: [{ type: "text", text: `Module '${name}' deleted.` }] };
  }
);

server.tool(
  "list_project_modules",
  "List modules configured for a project",
  { project_path: z.string().describe("Absolute path to the project directory") },
  async ({ project_path }) => {
    const output = run("ai-inst project status", project_path);
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "add_project_module",
  "Add modules to a project",
  {
    project_path: z.string().describe("Absolute path to the project directory"),
    modules: z.array(z.string()).describe("Module names to add"),
  },
  async ({ project_path, modules }) => {
    const output = run(`ai-inst project add ${modules.join(" ")}`, project_path);
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "remove_project_module",
  "Remove modules from a project",
  {
    project_path: z.string().describe("Absolute path to the project directory"),
    modules: z.array(z.string()).describe("Module names to remove"),
  },
  async ({ project_path, modules }) => {
    const output = run(`ai-inst project rm ${modules.join(" ")}`, project_path);
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool(
  "build",
  "Build instruction files for a project",
  { project_path: z.string().describe("Absolute path to the project directory") },
  async ({ project_path }) => {
    const output = run("ai-inst build", project_path);
    return { content: [{ type: "text", text: output }] };
  }
);

server.tool("sync", "Sync rules repository (pull + push)", {}, async () => {
  const output = run("ai-inst repo sync");
  return { content: [{ type: "text", text: output }] };
});

// ─── Start ───────────────────────────────────────────────────────────────────

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("MCP server error:", err);
  process.exit(1);
});
