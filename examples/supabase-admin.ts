// lib/supabase/admin.ts
// secret key를 쓰는 관리자 클라이언트. 'server-only' 덕분에 클라이언트 컴포넌트에서
// import 하면 빌드가 실패합니다. (npm i server-only)
import 'server-only'
import { createClient } from '@supabase/supabase-js'

export const supabaseAdmin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SECRET_KEY!, // 서버에서만 읽힘
)
