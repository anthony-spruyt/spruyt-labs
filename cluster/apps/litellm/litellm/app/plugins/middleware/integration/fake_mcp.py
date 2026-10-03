"""Minimal streamable-HTTP MCP server for the integration proxy, started after the proxy is ready."""

from mcp.server.mcpserver import MCPServer

mcp = MCPServer("it")


@mcp.tool()
def echo(text: str) -> str:
    return f"echo: {text}"


if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="127.0.0.1", port=8098, stateless_http=True, json_response=True)
