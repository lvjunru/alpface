//
//  MyFavoriteViewController.swift
//  Alpface
//
//  Created by swae on 2018/4/6.
//  Copyright © 2018年 alpface. All rights reserved.
//

import UIKit

class MyFavoriteViewController: UserProfileChildCollectionViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
    }
    override func titleForEmptyDataView() -> String? {
        return "TA还没有喜欢的作品哦~"
    }

}
