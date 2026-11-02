//
//  StoreFallback.swift
//
//  저장소를 열지 못한 날에도 앱이 켜지게 한다.
//
//  예전에는 여기서 fatalError 로 죽었다. 그러면 마이그레이션 한 번 어긋난 사용자는
//  켤 때마다 죽고, 기기 안에 멀쩡히 있는 기록도 못 본다.
//  이제는 디스크의 기록은 건드리지 않고 이번 실행만 메모리에서 열고, 사용자에게 그 사실을 알린다.
//  (다음 실행이나 고친 업데이트에서 원래 저장소가 다시 열리면 기록은 그대로다)
//

import SwiftUI
import SwiftData

enum StoreFallback {
    /// 이번 실행이 임시(메모리) 저장소로 열렸는가
    private(set) static var isActive = false

    static func memoryContainer(schema: Schema, after error: Error) -> ModelContainer {
        isActive = true
        print("⚠️ 저장소를 열지 못해 이번 실행은 메모리에서 엽니다: \(error)")
        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            )
        } catch {
            // 메모리 저장소마저 안 되는 건 스키마 자체가 잘못된 것 — 개발 중에 바로 드러난다
            fatalError("메모리 저장소도 열지 못함: \(error)")
        }
    }
}

extension View {
    /// 임시 저장소로 열렸으면 한 번 알린다. 앱의 맨 바깥 화면에 붙인다.
    func storeFallbackNotice() -> some View {
        modifier(StoreFallbackNotice())
    }
}

private struct StoreFallbackNotice: ViewModifier {
    @State private var isPresented = StoreFallback.isActive

    func body(content: Content) -> some View {
        content.alert("기록을 열지 못했어요", isPresented: $isPresented) {
        } message: {
            Text("저장된 기록은 지워지지 않았어요. 다만 지금 적는 내용은 저장되지 않으니, 앱을 껐다 켜 보세요.")
        }
    }
}
