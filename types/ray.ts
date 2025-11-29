export interface RayItem {
  id: string;
  created_at: string;
  title: string;
  content: string;
  zone: string;
  subzone: string | null;
  kind: string;
  tags?: string | null;
  source: "assistant_answer" | "user_note";
}

