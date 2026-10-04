import Foundation
import SwiftData

@main
struct ReleaseDataChecks {
    static let body = "# 中文 Prompt\n**Markdown** café 😀\n\n保留空行与 {{变量}}。\n"

    @MainActor
    static func main() throws {
        guard let isolated = ProcessInfo.processInfo.environment["OTATO_QA_LIBRARY_ROOT"],
              isolated.contains("otato-release-data-") else {
            fatalError("These checks require an isolated temporary library.")
        }
        let root = URL(fileURLWithPath: isolated, isDirectory: true)
        let container = try PromptPersistence.makeContainer()
        let context = container.mainContext
        let archive = root.appendingPathComponent("fixture.otatoarchive")
        switch CommandLine.arguments[1] {
        case "seed":
            let parent = Folder(name: "父文件夹")
            let child = Folder(name: "子文件夹", parentID: parent.id)
            context.insert(parent); context.insert(child)
            let prompt = try PromptLibrary.createPrompt(in: context, title: "持久化示例",
                content: body, folderID: child.id, tagNames: ["中文", "Café"])
            try PromptLibrary.setFavorite(true, for: prompt, in: context)
            let image = Data(base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
            let cover = try PromptStorage.saveCoverAsset(data: image)
            try PromptLibrary.setCover(cover, for: prompt, in: context)
            let legacy = Prompt(title: "旧 TXT 记录", content: body, formatRaw: "txt", deletedAt: .now)
            context.insert(legacy)
            let md = root.appendingPathComponent("导入.md")
            let txt = root.appendingPathComponent("导入.txt")
            try Data(body.utf8).write(to: md); try Data(body.utf8).write(to: txt)
            let imported = try PromptTextTransfer.importFiles([md, txt], into: context, folderID: child.id)
            precondition(imported.count == 2 && imported.allSatisfy { $0.content == body })
            let bad = root.appendingPathComponent("错误.txt")
            try Data([0xff, 0xfe, 0xff]).write(to: bad)
            do {
                _ = try PromptTextTransfer.importFiles([md, bad], into: context)
                fatalError("Invalid UTF-8 was accepted.")
            } catch PromptTextTransfer.TransferError.invalidEncoding { }
            let count = try context.fetchCount(FetchDescriptor<Prompt>())
            precondition(count == 4)
            try context.save()
            try PromptArchiveService.createArchive(prompts: context.fetch(FetchDescriptor<Prompt>()),
                folders: context.fetch(FetchDescriptor<Folder>()), tags: context.fetch(FetchDescriptor<Tag>()),
                at: archive)
            let summary = try PromptArchiveService.inspectArchive(at: archive)
            precondition(summary.promptCount == 4 && summary.trashedPromptCount == 1)
            precondition(summary.folderCount == 2 && summary.tagCount == 2 && summary.coverCount == 1)
            print("PASS: saved disk library, batch import rollback and complete backup")
        case "reopen", "verify-restored":
            let prompts = try context.fetch(FetchDescriptor<Prompt>())
            precondition(prompts.count == 4)
            let saved = prompts.first { $0.title == "持久化示例" }!
            precondition(saved.content == body && saved.isFavorite)
            precondition(Set(saved.tagNames) == ["中文", "Café"])
            let legacy = prompts.first { $0.title == "旧 TXT 记录" }!
            precondition(legacy.formatRaw == "txt" && legacy.deletedAt != nil && legacy.content == body)
            let folders = try context.fetch(FetchDescriptor<Folder>())
            let child = folders.first { $0.name == "子文件夹" }!
            let parent = folders.first { $0.name == "父文件夹" }!
            precondition(child.parentID == parent.id && saved.folderID == child.id)
            precondition(PromptStorage.loadCover(at: saved.coverPath!) != nil)
            if CommandLine.arguments[1] == "reopen" {
                let directory = root.appendingPathComponent("导出", isDirectory: true)
                let exports = try PromptTextTransfer.writeCollection(
                    prompts: prompts.filter { $0.deletedAt == nil }, folders: folders, to: directory)
                precondition(exports.count == 3 && Set(exports).count == 3)
                for file in exports {
                    let text = try String(contentsOf: file, encoding: .utf8)
                    precondition(text == body)
                }
                try PromptLibrary.apply(.restore, to: [legacy], in: context)
                precondition(legacy.deletedAt == nil)
                try PromptLibrary.apply(.trash, to: [legacy], in: context)
                print("PASS: reopen across processes, folder/tag/cover/body fidelity, unique exports, trash/restore")
            } else {
                print("PASS: restored library persists across another process restart")
            }
        case "restore":
            let corrupt = root.appendingPathComponent("corrupt.otatoarchive")
            var bytes = try Data(contentsOf: archive)
            bytes[bytes.count - 1] ^= 1
            try bytes.write(to: corrupt)
            let before = Set(try context.fetch(FetchDescriptor<Prompt>()).map(\.id))
            do {
                _ = try PromptArchiveService.restoreArchive(at: corrupt, into: context)
                fatalError("A corrupt backup was accepted.")
            } catch ArchiveError.checksumMismatch { }
            let unchanged = Set(try context.fetch(FetchDescriptor<Prompt>()).map(\.id))
            precondition(unchanged == before)
            let sentinel = try PromptLibrary.createPrompt(in: context, title: "恢复前新增", content: "safety backup")
            let summary = try PromptArchiveService.restoreArchive(at: archive, into: context)
            precondition(summary.promptCount == 4 && summary.coverCount == 1)
            let safety = try PromptArchiveService.inspectArchive(at: summary.preRestoreBackupURL!)
            precondition(safety.promptCount == 5)
            let restored = try context.fetch(FetchDescriptor<Prompt>())
            precondition(!restored.contains { $0.id == sentinel.id })
            print("PASS: corrupt archive leaves data untouched; restore preserves a full safety backup")
        default: fatalError("Unknown check phase.")
        }
    }
}
