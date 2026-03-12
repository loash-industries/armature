import { Card, CardHeader, CardContent, Badge } from "@awar.dev/ui";

function App() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background font-mono text-foreground">
      <Card className="w-80">
        <CardHeader className="text-center text-2xl font-bold">
          armature
        </CardHeader>
        <CardContent className="text-center">
          <Badge variant="outline">DAO Framework</Badge>
        </CardContent>
      </Card>
    </div>
  );
}

export default App;
