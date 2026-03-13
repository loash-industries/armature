import { useMemo } from "react";
import { useNavigate } from "@tanstack/react-router";
import {
  GraphCanvas,
  GraphLegend,
  useNodesState,
  useEdgesState,
  Handle,
  Position,
} from "@awar.dev/ui";
import type { Node, NodeProps, NodeTypes, Edge } from "@awar.dev/ui";
import type { GraphEdgeData } from "@awar.dev/ui";
import { Card, Badge } from "@awar.dev/ui";
import type { DAOHierarchy } from "@/types/dao";

interface DAONodeData extends Record<string, unknown> {
  label: string;
  status: "Active" | "Migrating";
  isPaused: boolean;
  childCount: number;
  daoId: string;
}

function DAONodeComponent({ data }: NodeProps<Node<DAONodeData>>) {
  const navigate = useNavigate();

  return (
    <div
      className="cursor-pointer"
      onClick={() => {
        navigate({
          to: "/dao/$daoId",
          params: { daoId: data.daoId },
        });
      }}
    >
      <Handle type="target" position={Position.Top} />
      <Card className="min-w-[160px] border-2 p-3">
        <div className="flex flex-col gap-1">
          <span className="text-sm font-bold">{data.label}</span>
          <div className="flex gap-1">
            <Badge variant="outline" className="text-xs">
              {data.status}
            </Badge>
            {data.isPaused && (
              <Badge variant="destructive" className="text-xs">
                Paused
              </Badge>
            )}
          </div>
          {data.childCount > 0 && (
            <span className="text-muted-foreground text-xs">
              {data.childCount} sub-DAO{data.childCount !== 1 ? "s" : ""}
            </span>
          )}
        </div>
      </Card>
      <Handle type="source" position={Position.Bottom} />
    </div>
  );
}

const nodeTypes: NodeTypes = {
  daoNode: DAONodeComponent,
};

function buildGraph(hierarchy: DAOHierarchy) {
  const nodes: Node<DAONodeData>[] = [];
  const edges: Edge<GraphEdgeData>[] = [];

  nodes.push({
    id: hierarchy.root.daoId,
    type: "daoNode",
    position: { x: 0, y: 0 },
    data: {
      label: hierarchy.root.name,
      status: hierarchy.root.status,
      isPaused: hierarchy.root.controllerPaused || hierarchy.root.executionPaused,
      childCount: hierarchy.root.childCount,
      daoId: hierarchy.root.daoId,
    },
  });

  const childCount = hierarchy.children.length;
  const spacing = 250;
  const startX = -((childCount - 1) * spacing) / 2;

  hierarchy.children.forEach((child, i) => {
    const isPaused = child.controllerPaused || child.executionPaused;

    nodes.push({
      id: child.daoId,
      type: "daoNode",
      position: { x: startX + i * spacing, y: 200 },
      data: {
        label: child.name,
        status: child.status,
        isPaused,
        childCount: child.childCount,
        daoId: child.daoId,
      },
    });

    edges.push({
      id: `${hierarchy.root.daoId}-${child.daoId}`,
      source: hierarchy.root.daoId,
      target: child.daoId,
      data: {
        stroke: isPaused ? "var(--color-muted-foreground)" : "var(--color-primary)",
        dash: isPaused ? "6 3" : undefined,
        animated: !isPaused,
      },
    });
  });

  return { nodes, edges };
}

const legendItems = [
  { label: "Active Control", color: "var(--color-primary)" },
  { label: "Paused", color: "var(--color-muted-foreground)", dash: "6 3" },
];

export function SubDAOGraph({ hierarchy }: { hierarchy: DAOHierarchy }) {
  const { nodes: initialNodes, edges: initialEdges } = useMemo(
    () => buildGraph(hierarchy),
    [hierarchy],
  );

  const [nodes, , onNodesChange] = useNodesState(initialNodes);
  const [edges, , onEdgesChange] = useEdgesState(initialEdges);

  return (
    <div className="relative h-[500px] w-full">
      <GraphCanvas
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        fitView
      >
        <GraphLegend title="Control Status" items={legendItems} />
      </GraphCanvas>
    </div>
  );
}
