// app/reservations/actions.ts
// 'use server' 파일에서 export 한 함수는 누구나 직접 호출할 수 있는 공개 API입니다.
// 함수 안에서 매번 로그인과 "주인"을 다시 확인하세요.
'use server'
import { createClient } from '@/lib/supabase/server'

export async function cancelReservation(id: string) {
  const supabase = await createClient()
  // getSession()은 쿠키 값을 검증 없이 믿으므로 서버 검증용으로 쓰지 않습니다.
  // getClaims()(권장) 또는 getUser()로 검증합니다.
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) throw new Error('로그인이 필요합니다')

  const { data, error } = await supabase
    .from('reservations')
    .update({ status: 'cancelled' })
    .eq('id', id)
    .eq('user_id', user.id) // 핵심: 주인 조건
    .select('id')
  if (error) throw new Error('취소에 실패했습니다') // DB 오류 원문은 사용자에게 보내지 않음
  // RLS에 막힌 수정은 오류 없이 0건으로 끝나므로 직접 확인
  if (!data?.length) throw new Error('예약을 찾을 수 없습니다')
}
