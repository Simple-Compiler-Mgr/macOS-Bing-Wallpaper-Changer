//
//  ContentView.swift
//  BingWallpaperChanger
//
//  Created by zuole on 9/15/24.
//

import SwiftUI
import AppKit

@main
struct BingWallpaperChangerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()  // 隐藏主窗口
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let wallpaperManager = WallpaperManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "Wallpaper")
            button.action = #selector(showMenu)
        }

        updateWallpaper()

        Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
            self.updateWallpaper()
        }
    }

    @objc func showMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "立即更新壁纸", action: #selector(updateWallpaper), keyEquivalent: "U"))
        menu.addItem(NSMenuItem(title: "设置自定义API", action: #selector(showCustomAPIDialog), keyEquivalent: "C"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "Q"))

        statusItem?.menu = menu
    }

    @objc func updateWallpaper() {
        wallpaperManager.downloadAndSetWallpaper()
    }

    @objc func showCustomAPIDialog() {
        let alert = NSAlert()
        alert.messageText = "设置自定义 API 源"
        alert.informativeText = "输入自定义壁纸 API 的 URL："
        
        let inputTextField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        inputTextField.stringValue = wallpaperManager.customAPI
        alert.accessoryView = inputTextField
        
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            wallpaperManager.customAPI = inputTextField.stringValue
            print("自定义 API 保存: \(wallpaperManager.customAPI)")
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(self)
    }
}

class WallpaperManager: ObservableObject {
    @AppStorage("customAPI") var customAPI: String = ""

    func downloadAndSetWallpaper() {
        // 使用自定义 API URL，如果未提供，则使用默认 Bing API
        let apiUrl = customAPI.isEmpty ? "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US" : customAPI
        
        guard let url = URL(string: apiUrl) else {
            print("URL 无效")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("请求失败: \(error)")
                return
            }
            
            guard let data = data else {
                print("未收到数据")
                return
            }

            // 尝试先用 Bing API 的格式解析
            if !self.parseBingResponse(data: data) {
                // 如果解析失败，尝试使用自定义 API 的格式解析
                self.parseCustomAPIResponse(data: data)
            }
        }
        
        task.resume()
    }
    
    // 尝试解析 Bing API 响应数据
    func parseBingResponse(data: Data) -> Bool {
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let images = json["images"] as? [[String: Any]],
               let imageUrlString = images.first?["url"] as? String {
                
                // 拼接完整的图片 URL 并下载图片
                let imageUrl = "https://www.bing.com" + imageUrlString
                self.downloadImage(from: URL(string: imageUrl)!)
                return true
                
            } else {
                print("解析 Bing API JSON 失败")
                return false
            }
        } catch {
            print("Bing API JSON 解析错误: \(error)")
            return false
        }
    }
    
    // 解析自定义 API 响应数据
    func parseCustomAPIResponse(data: Data) {
        do {
            // 假设自定义 API 返回的 JSON 数据中有一个 "imageUrl" 字段，包含图片的 URL
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let imageUrlString = json["imageUrl"] as? String {
                
                guard let imageUrl = URL(string: imageUrlString) else {
                    print("自定义 API 返回的图片 URL 无效")
                    return
                }
                
                // 下载并设置壁纸
                self.downloadImage(from: imageUrl)
                
            } else {
                print("解析自定义 API JSON 失败")
            }
        } catch {
            print("自定义 API JSON 解析错误: \(error)")
        }
    }

    func downloadImage(from url: URL) {
        // 清理 tmp 文件夹中的旧图片
        clearTemporaryDirectory()

        let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
            if let error = error {
                print("下载图片失败: \(error)")
                return
            }
            
            guard let localURL = localURL else {
                print("未找到下载的文件")
                return
            }

            // 确保下载的是图片文件
            if let mimeType = response?.mimeType, mimeType.hasPrefix("image") {
                let fileManager = FileManager.default
                let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(response?.suggestedFilename ?? "bingWallpaper.jpg")

                do {
                    try fileManager.moveItem(at: localURL, to: destinationURL)
                    print("图片保存路径: \(destinationURL.path)")

                    self.setDesktopWallpaper(imagePath: destinationURL)

                } catch {
                    print("文件处理失败: \(error)")
                }
            } else {
                print("下载的文件不是图片")
            }
        }

        task.resume()
    }

    // 清理 tmp 文件夹中的旧图片
    func clearTemporaryDirectory() {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        
        do {
            let tmpFiles = try fileManager.contentsOfDirectory(atPath: tempDirectory.path)
            for file in tmpFiles {
                let filePath = tempDirectory.appendingPathComponent(file).path
                try fileManager.removeItem(atPath: filePath)
            }
            print("已清理 tmp 文件夹")
        } catch {
            print("清理 tmp 文件夹失败: \(error)")
        }
    }

    func setDesktopWallpaper(imagePath: URL) {
        do {
            guard let screen = NSScreen.main else {
                print("未找到主屏幕")
                return
            }

            try NSWorkspace.shared.setDesktopImageURL(imagePath, for: screen, options: [:])
            print("壁纸已更换")
        } catch {
            print("设置壁纸失败: \(error)")
        }
    }
}
