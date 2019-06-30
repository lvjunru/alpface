//
//  ALPConstans.swift
//  Alpface
//
//  Created by swae on 2018/3/25.
//  Copyright © 2018年 alpface. All rights reserved.
//

import Foundation


struct ALPConstans {
    static var animationDuration: Double {
        get {
            return 0.36
        }
    }
    
    struct AuthKeys {
        /// 存储登录用户信息的key，如果此key获取的value为nil则说明用户未登录
        static let ALPLoginUserInfoKey = "LoginUserInfoKey"
        static let ALPCsrfmiddlewaretokenKey = "csrfmiddlewaretoken"
        static let ALPAuthTokenKey = "token"
        static let ALPAuthUserNameKey = "username"
        static let ALPAuthenticationUserKey = "ALPAuthenticationUserKey"
        /// 用户授权出现问题，需要重新登录
        static let ALPAuthPermissionErrorValue = "<h1>403 Forbidden</h1>"
    }
    
    struct HttpRequestURL {
        static let ALPSiteURLString = "http://10.211.55.4:8888"
        // 登录
//        static let login = "\(ALPSiteURLString)" + "/account/auth/login/"
        static let login = "\(ALPSiteURLString)" + "/login/"
        // 注册
        static let register = "\(ALPSiteURLString)" + "/users/"
        static let updateProfile = "\(ALPSiteURLString)" + "/account/user/update/"
        static let getCsrfToken = "\(ALPSiteURLString)" + "/account/auth/csrf"
        static let getAuthToken = "\(ALPSiteURLString)" + "/account/auth/authtoken"
        static let getRadomVideos = "\(ALPSiteURLString)" + "/video/getAll"
        static let uoloadVideo = "\(ALPSiteURLString)" + "/video/new"
        static let discoverUserByUsername = "\(ALPSiteURLString)" + "/account/discover/search"
        static let getVideoByUserId = "\(ALPSiteURLString)" + "/video/getVideoByUserId"
        
    }
}


