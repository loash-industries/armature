import { useParams, Link } from "@tanstack/react-router";
import {
  Breadcrumb,
  BreadcrumbList,
  BreadcrumbItem,
  BreadcrumbSeparator,
} from "@/components/ui/breadcrumb";
import { useParentDAO } from "@/hooks/useSubDAOs";
import { useDaoSummary } from "@/hooks/useDao";

export function SubDAOBreadcrumb() {
  const { daoId } = useParams({ strict: false });
  const { data: parent } = useParentDAO(daoId ?? "");
  const { data: dao } = useDaoSummary(daoId ?? "");

  if (!parent) return null;

  return (
    <Breadcrumb>
      <BreadcrumbList>
        <BreadcrumbItem>
          <Link
            to="/dao/$daoId"
            params={{ daoId: parent.parentId }}
            className="text-muted-foreground hover:text-foreground text-sm transition-colors"
          >
            {parent.parentName}
          </Link>
        </BreadcrumbItem>
        <BreadcrumbSeparator />
        <BreadcrumbItem>
          <span className="text-foreground text-sm font-medium">
            {dao?.charterName ?? "SubDAO"}
          </span>
        </BreadcrumbItem>
      </BreadcrumbList>
    </Breadcrumb>
  );
}
