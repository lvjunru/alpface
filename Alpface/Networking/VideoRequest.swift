//
//  VideoRequest.swift
//  Alpface
//
//  Created by swae on 2018/3/31.
//  Copyright © 2018年 alpface. All rights reserved.
//

import UIKit
import Alamofire

public typealias ALPHttpResponseBlock = (Any?) -> Void
public typealias ALPHttpErrorBlock = (_ error: Error?) -> ()
public typealias ALPProgressHandler = (Progress) -> Void
open class VideoRequest: NSObject {
    static public let shared = VideoRequest()
    
    public func getRadomVideos(success: ALPHttpResponseBlock?, failure: ALPHttpErrorBlock?){
        
        let url = ALPConstans.HttpRequestURL.getRadomVideos
        HttpRequestHelper.request(method: .get, url: url, parameters: nil) { (response, error) in
            
            if error != nil {
                guard let fail = failure else {
                    return
                }
                DispatchQueue.main.async {
                    fail(error)
                }
                return
            }
            
            guard let succ = success else {
                return
            }
            guard let jsonString = response as? String else {
                DispatchQueue.main.async {
                    succ(nil)
                }
                return
            }
            
            let jsonDict =  self.getDictionaryFromJSONString(jsonString: jsonString)
            guard let dataDict = jsonDict["data"] as? [String : Any] else {
                DispatchQueue.main.async {
                    succ(nil)
                }
                print("data不存在或者不是字典类型")
                return
            }
            guard let videoList = dataDict["videos"] as? [[String : Any]] else {
                DispatchQueue.main.async {
                    succ(nil)
                }
                print("videos不存在或者不是字典类型")
                return
            }
            var list: [VideoItem] = [VideoItem]()
            for dict in videoList {
                let video = VideoItem(dict: dict)
                list.append(video)
            }
            DispatchQueue.main.async {
                succ(list)
            }
            
        }
    }
    
    
    public func discoverUserByUsername(username: String, success: ALPHttpResponseBlock?, failure: ALPHttpErrorBlock?){
        let url = ALPConstans.HttpRequestURL.discoverUserByUsername
//        guard let authUser = AuthenticationManager.shared.loginUser else {
//            if let fail = failure {
//                let e = NSError(domain: "ErrorNOTFoundauthUser", code: 404, userInfo: nil)
//                fail(e)
//            }
//            return
//        }
        
        let parameters = [
            "username": username,
            "type": "1",
            
        ]  as NSMutableDictionary
        if let authUser = AuthenticationManager.shared.loginUser {
            parameters["auth_username"] = authUser.username!
        }

        HttpRequestHelper.request(method: .get, url: url, parameters: parameters) { (response, error) in
            if let error = error {
                guard let fail = failure else { return }
                DispatchQueue.main.async {
                    fail(error)
                }
                return
            }
            
            guard let userInfo = response as? String else {
                guard let fail = failure else { return }
                DispatchQueue.main.async {
                    fail(NSError(domain: NSURLErrorDomain, code: 403, userInfo: nil))
                }
                
                return
            }
            
            let jsonDict =  self.getDictionaryFromJSONString(jsonString: userInfo)
            if let userDict = jsonDict["data"] as? [String : Any] {
                guard let succ = success else { return }
                let user = User(dict: userDict)
                DispatchQueue.main.async {
                    succ(user)
                }
            }
            else {
                guard let fail = failure else { return }
                DispatchQueue.main.async {
                    fail(NSError(domain: NSURLErrorDomain, code: 403, userInfo: nil))
                }
            }
        }
    }
    /// 发布视频
    /// @param title 发布的标题
    /// @param describe 发布的内容
    /// @param videoPath 视频文件w本地路径
    /// @param progress 进度回调
    /// @param success 成功回调
    /// @param failure 失败回调
    /// @param coverStartTime 封面从某秒开始
    public func releaseVideo(title: String, describe: String, coverStartTime: TimeInterval, videoPath: String,longitude: Double = 0, latitude: Double = 0 , poi_name: String="", poi_address: String="", progress: ALPProgressHandler?, success: ALPHttpResponseBlock?, failure: ALPHttpErrorBlock?) {
        
        if AuthenticationManager.shared.isLogin == false {
            return
        }
        
        let file = VideoFile(path: videoPath)
        guard let data = file.readAll() else {
            return
        }
        file.close()
        
        let urlString = ALPConstans.HttpRequestURL.uoloadVideo
        var parameters = Dictionary<String, Any>.init()
        parameters["title"] = title
        parameters["describe"] = describe
        // 播放封面的时间戳 默认5秒
        parameters["coverDuration"] = 2.5
        // 封面起始的时间戳
        parameters["coverStartTime"] = coverStartTime
        
        if longitude != 0 &&
            latitude != 0 &&
            poi_name.count > 0 &&
            poi_address.count > 0 {
            parameters["longitude"] = longitude
            parameters["latitude"] = latitude
            parameters["poi_name"] = poi_name
            parameters["poi_address"] = poi_address
        }
        
        let url = URL(string: urlString)
       Alamofire.upload(multipartFormData: { (multipartFormData) in
            
            multipartFormData.append(data, withName:"video", fileName:file.displayName!, mimeType:"video/mp4")
            
            // 遍历字典
            for (key, value) in parameters {
                var value_string: String!
                if value is String {
                    value_string = value as? String
                }
                else {
                    value_string = "\(value)"
                }
                
                let _datas: Data = value_string.data(using:String.Encoding.utf8)!
                multipartFormData.append(_datas, withName: key)
                
            }
            
        }, to: url!) { (result) in
            switch result {
            case .success(let upload,_, _):
                upload.uploadProgress(queue: DispatchQueue.main, closure: { (p) in
                    if let prog = progress {
                        prog(p)
                    }
                }).responseJSON(completionHandler: { (response) in
                    if let value = response.result.value as? NSDictionary {
                        if value["status"] as? String == "success" {
                            if let suc = success {
                                if let data = value["data"] as? NSDictionary {
                                    if let video = data["video"] as? NSDictionary {
                                        let v = VideoItem(dict: video as! [String : Any])
                                        suc(v)
                                        return
                                    }
                                }
                                
                            }
                        }
                    }
                    guard let fail = failure else { return }
                    fail(NSError(domain: NSURLErrorDomain, code: 403, userInfo: nil))
                })
            case .failure(let error):
                
                guard let fail = failure else { return }
                DispatchQueue.main.async {
                    fail(error)
                }
            }
        }
    }
    
    public func getVideoByUserId(userId: String, success: ALPHttpResponseBlock?, failure: ALPHttpErrorBlock?){
        
        let url = ALPConstans.HttpRequestURL.getVideoByUserId
        HttpRequestHelper.request(method: .get, url: url, parameters: ["user_id": userId]) { (response, error) in
            
            if error != nil {
                guard let fail = failure else {
                    return
                }
                DispatchQueue.main.async {
                    fail(error)
                }
                return
            }
            
            guard let succ = success else {
                return
            }
            guard let jsonString = response as? String else {
                DispatchQueue.main.async {
                    succ(nil)
                }
                return
            }
            
            let jsonDict =  self.getDictionaryFromJSONString(jsonString: jsonString)
            guard let dataDict = jsonDict["data"] as? [String : Any] else {
                DispatchQueue.main.async {
                    succ(nil)
                }
                print("data不存在或者不是字典类型")
                return
            }
            guard let videoList = dataDict["videos"] as? [[String : Any]] else {
                DispatchQueue.main.async {
                    succ(nil)
                }
                print("videos不存在或者不是字典类型")
                return
            }
            var list: [VideoItem] = [VideoItem]()
            for dict in videoList {
                let video = VideoItem(dict: dict)
                list.append(video)
            }
            DispatchQueue.main.async {
                succ(list)
            }
            
        }
    }
}
