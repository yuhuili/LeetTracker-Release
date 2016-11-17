//
//  LTCore.swift
//  LeetTracker
//
//  Created by Alexander Li on 2016-11-04.
//  Copyright © 2016 Yuhui Li. All rights reserved.
//

import Cocoa
import SQLite
import Alamofire
import Kanna
import JavaScriptCore

struct Constants {
    static let validGitRepoCheckCodeTemplate = "git -C %@ rev-parse"
    static let statusTextTemplate = "Status: %@"
    
    static let questionListJSONURL = "https://leetcode.com/api/problems/algorithms/"
    static let validAccountURL = "https://leetcode.com/submissions/"
    static let questionURL = "https://leetcode.com/problems/%@/"
    static let questionSpecificSubmissionListURL = "https://leetcode.com/problems/%@/submissions/"
    static let submissionPageURL = "https://leetcode.com/submissions/detail/%@/"
    
    static let lcQuestionTitleKey = "question__title"
    static let lcQuestionTitleSlugKey = "question__title_slug"
    static let lcQuestionIdKey = "question_id"
    static let lcSubmissionIdKey = "submission_id"
    
    static let lcUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/54.0.2840.71 Safari/537.36"
    
    static let readMeTitleLine = "# %@. %@\n"
    
    static let submissionsPre = "## Submissions\n|#|Status|Run Time|\n|---:|:---:|:---:|\n"
    static let submissionRow = "|%@|%@|%@|\n"
}

enum LTCoreError: Error {
    case NoCookie
    case ResponseNoJSONQuestionList
    case ResponseNoHTMLSubmissionList
    case ResponseJSONMalformed
    case LocalCompletedQuestionsDicMalformed
}

class LTCore: NSObject {
    
    static let sharedInstance = LTCore()
    
    var lcCookie : String = ""
    
    var gitRepoPath : String = ""
    
    var databasePath : String = ""
    
    var questionsDicById = Dictionary<String, Dictionary<String, String>>()
    
    var questionsDicByTitleSlug = Dictionary<String, Dictionary<String, String>>()
    
    var submissionPageRequests = Dictionary<String, DataRequest>()
    
    var submissionsDic = Dictionary<String, [Dictionary<String, String>]>()
    
    func questionId(titleSlug: String) -> String {
        if let i = questionsDicByTitleSlug[titleSlug], let j = i[Constants.lcQuestionIdKey] {
            return j
        }
        return ""
    }
    
    func questionTitleSlug(questionId: String) -> String {
        if let i = questionsDicById[questionId], let j = i[Constants.lcQuestionTitleSlugKey] {
            return j
        }
        return ""
    }
    
    func questionTitle(questionId: String) -> String {
        if let i = questionsDicById[questionId], let j = i[Constants.lcQuestionTitleKey] {
            return j
        }
        return ""
    }
    
    func submissionIdInDatabase(_ submissionId: String) -> Bool {
        do {
            let db = try Connection(databasePath)
            let submissions = Table("submissions")
            let result = try db.prepare(submissions)
            
            for _ in result {
                return true
            }
            
            return false
            
        } catch {
            return false
        }
    }
    
    func addSubmissionIdToDatabase(_ submissionId: String) -> Void {
        do {
            let db = try Connection(databasePath)
            let submissions = Table("submissions")
            let id = Expression<String>("submission_id")
            
            let insert = submissions.insert(id <- submissionId)
            
            _ = try db.run(insert)
            
        } catch {
            // BAD
        }
    }
    
    func isValidGitRepo(path: String) -> Bool {
        
        if !path.hasPrefix("/") {
            return false
        }
        
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: String(format: "%@.git", path), isDirectory: &isDir) {
            return isDir.boolValue
        }
        return false
    }
    
    func isValidDatabasePath(path: String) -> Bool {
        
        if !path.hasPrefix("/") {
            return false
        }
        
        if FileManager.default.fileExists(atPath: path, isDirectory: nil) {
            do {
                let db = try Connection(path)
                let submissions = Table("submissions")
                let id = Expression<String>("submission_id")
                
                try db.run(submissions.create(ifNotExists: true) { t in
                    t.column(id, unique: true)
                })
                return true;
            } catch {
                return false;
            }
        } else {
            return false
        }
    }
    
    func isValidLCAccount(cookie: String, completion: @escaping (_: Bool) -> Void) -> Void {
        // Look for /accounts/login/ in response
        
        let u = URL(string: Constants.validAccountURL)!
        let mutableUrlRequest = URLRequest.lcGetRequest(url: u, cookie: cookie, userAgent: Constants.lcUserAgent)
        
        Alamofire.request(mutableUrlRequest).responseString { response in
            
            if !response.result.isSuccess {
                completion(false)
                return
            }
            
            if let rr = response.result.value {
                if (rr.range(of: "/accounts/login/") != nil) {
                    completion(false)
                } else {
                    self.lcCookie = cookie
                    completion(true)
                }
            }
            
        }
    }
    
    func startProcessing(gitrepo: String, database: String, completion: @escaping (_: Bool, _: NSError?) -> Void) -> Void {
        
        gitRepoPath = gitrepo
        databasePath = database
        
        do {
            try getQuestionList(completion: { (error, dictionary) in
                if let JSON = dictionary {
                    self.processQuestionList(JSON: JSON, completion: { (error, dic) in
                        
                    })
                } else {
                    print("Error: No JSON")
                    completion(false, error)
                }
            })
        } catch {
            print("Error: No JSON")
            completion(false, NSError(domain: "LTCore", code: -1, userInfo: ["error": LTCoreError.ResponseNoJSONQuestionList]))
        }
    }
    
    func getQuestionList(completion: @escaping (_: NSError?, _: Dictionary<String, AnyObject>?) -> Void) throws -> Void {
        
        guard !lcCookie.isEmpty else {
            throw LTCoreError.NoCookie
        }
        
        let u = URL(string: Constants.questionListJSONURL)!
        let mutableUrlRequest = URLRequest.lcGetRequest(url: u, cookie: lcCookie, userAgent: Constants.lcUserAgent)
        
        Alamofire.request(mutableUrlRequest).responseJSON { response  in
            if let JSON = response.result.value as? Dictionary<String, AnyObject> {
                completion(nil, JSON)
            } else {
                completion(NSError(domain: "LTCore", code: -1, userInfo: ["error": LTCoreError.ResponseNoJSONQuestionList]), nil)
            }
        }
        
    }
    
    func processQuestionList(JSON: Dictionary<String, AnyObject>, completion: @escaping (_: NSError?, _: Dictionary<String, AnyObject>?) -> Void) -> Void {
        
        // Check if malformed
        if (JSON["num_solved"] != nil) && (JSON["stat_status_pairs"] != nil) {
            
            if var numSolvedCounter = (JSON["num_solved"] as? NSNumber)?.intValue {
                while (numSolvedCounter > 0) {
                    if let list = JSON["stat_status_pairs"] as? [Dictionary<String, AnyObject>] {
                        
                        for dic in list {
                            if let status = dic["status"] as? String {
                                if status == "ac" {
                                    // This question is accepted
                                    var myDic = Dictionary<String, String>();
                                    if let stat = dic["stat"] as? [String:AnyObject],
                                        let question_id_number = stat[Constants.lcQuestionIdKey] as? NSNumber,
                                        let question_title = stat[Constants.lcQuestionTitleKey] as? String,
                                        let question_title_slug = stat[Constants.lcQuestionTitleSlugKey] as? String {
                                        myDic[Constants.lcQuestionIdKey] = String(question_id_number.intValue)
                                        myDic[Constants.lcQuestionTitleKey] = question_title
                                        myDic[Constants.lcQuestionTitleSlugKey] = question_title_slug
                                        
                                        questionsDicById[String(question_id_number.intValue)] = myDic
                                        questionsDicByTitleSlug[question_title_slug] = myDic
                                        
                                        numSolvedCounter -= 1
                                        
                                    } else {
                                        completion(NSError(domain: "LTCore", code: -1, userInfo: ["error": LTCoreError.ResponseJSONMalformed]), nil)
                                    }
                                    
                                }
                            }
                        }
                        
                        // For processSubmissionList
                        let completedQuestionCount = questionsDicById.count
                        
                        var completedRequestCount = 0
                        
                        
                        for (_, completedQuestion) in questionsDicById {
                            self.getQuestionInfo(questionId: completedQuestion[Constants.lcQuestionIdKey]!, questionTitle: completedQuestion[Constants.lcQuestionTitleKey]!, questionTitleSlug: completedQuestion[Constants.lcQuestionTitleSlugKey]!, completion: { (error, dic) in
                                
                                completedRequestCount += 1
                                if (completedRequestCount == completedQuestionCount) {
                                    self.prepareSubmissionList()
                                }
                            })
                            
                        }
                        
                    } else {
                        completion(NSError(domain: "LTCore", code: -1, userInfo: ["error": LTCoreError.ResponseJSONMalformed]), nil)
                    }
                }
                
            } else {
                completion(NSError(domain: "LTCore", code: -1, userInfo: ["error": LTCoreError.ResponseJSONMalformed]), nil)
            }
            
        } else {
            completion(NSError(domain: "LTCore", code: -1, userInfo: ["error": LTCoreError.ResponseJSONMalformed]), nil)
        }
    }
    
    func prepareSubmissionList() {
        
        for (_, completedQuestion) in questionsDicById {
            self.getSubmissionList(questionDic: completedQuestion, completion: { (error, dic) in
                if (self.submissionPageRequests.count == self.submissionsDic.count) {
                    self.processSubmissionList(completion: { (error, dic) in
                        
                        
                    })
                }
            })
        }
    }
    
    func getQuestionInfo(questionId: String, questionTitle: String, questionTitleSlug: String, completion: @escaping (_: NSError?, _: Dictionary<String, AnyObject>?) -> Void) -> Void {
        let u = URL(string: String(format: Constants.questionURL, questionTitleSlug))!
        let mutableUrlRequest = URLRequest.lcGetRequest(url: u, cookie: lcCookie, userAgent: Constants.lcUserAgent)
        
        Alamofire.request(mutableUrlRequest).responseString { response in
            if response.result.isSuccess {
                if let contents = response.result.value, let doc = HTML(html: contents, encoding: .utf8) {
                    
                    if let rawDesc = doc.css("meta[name=\"description\"]").first, let untrimmedDesc = rawDesc.toHTML {
                        
                        let beg = untrimmedDesc.index(untrimmedDesc.startIndex, offsetBy:34)
                        let end = untrimmedDesc.index(untrimmedDesc.endIndex, offsetBy:-3)
                        
                        let trimmedDesc = untrimmedDesc[beg...end]
                        
                        let finalDesc = trimmedDesc.replacingOccurrences(of: "\n\n\n\n", with: "\n\n")
                        
                        
                        
                        // Save File
                        let folderName = questionId + " " + questionTitle
                        let folderFullPath = self.gitRepoPath + folderName + "/"
                        let fileFullPath = folderFullPath + "README.md"
                        
                        // Create folder if necessary
                        let manager = FileManager.default
                        do {
                            try manager.createDirectory(atPath: folderFullPath, withIntermediateDirectories: false, attributes: nil)
                        } catch {
                            // BAD
                        }
                        
                        do {
                            manager.createFile(atPath: fileFullPath, contents: nil, attributes: nil)
                            
                            let fileData = String(format: Constants.readMeTitleLine, questionId, questionTitle) + finalDesc + "\n\n\n\n" + Constants.submissionsPre
                            
                            //print("Writing to: "+fileFullPath)
                            //print(fileData)
                            
                            try fileData.write(toFile: fileFullPath, atomically: false, encoding: String.Encoding.utf8)
                            
                            
                        } catch {
                            // BAD
                        }
                        
                        completion(nil, nil)
                    }
                    
                } else {
                    // BAD
                }
            } else {
                // BAD
            }
        }
    }
    
    func getSubmissionList(questionDic: Dictionary<String, String>, completion: @escaping (_: NSError?, _: Dictionary<String, AnyObject>?) -> Void) -> Void {
        if let question_id = questionDic[Constants.lcQuestionIdKey],
            let question_title = questionDic[Constants.lcQuestionTitleKey],
            let question_title_slug = questionDic[Constants.lcQuestionTitleSlugKey]{
            
            let u = URL(string: String(format: Constants.questionSpecificSubmissionListURL, question_title_slug))!
            let mutableUrlRequest = URLRequest.lcGetRequest(url: u, cookie: lcCookie, userAgent: Constants.lcUserAgent)
            
            let submissionPageRequest = Alamofire.request(mutableUrlRequest);
            
            submissionPageRequests[question_id] = submissionPageRequest
            
            submissionPageRequest.responseString { response  in
                self.submissionsDic[question_title_slug] = [Dictionary<String, String>]()
                
                if response.result.isSuccess, let contents = response.result.value {
                    if let doc = HTML(html: contents, encoding: .utf8) {
                        
                        for node in doc.css("tbody tr") {
                            if let trContents = node.toHTML, let tr = HTML(html: trContents, encoding: .utf8) {
                                
                                var submissionDic = Dictionary<String, String>()
                                
                                var index = 0
                                
                                for td in tr.css("td") {
                                    if (index==2) {
                                        
                                        // Get submission id
                                        if let subtd = td.innerHTML {
                                            let subMatches = subtd.matches(regex:"[0-9]{6,}")
                                            if subMatches.count != 1 {
                                                // THROW
                                            } else {
                                                submissionDic["submission_id"] = subMatches[0]
                                                
                                            }
                                        }
                                        
                                        // Get submission status
                                        if let subtd = td.innerHTML {
                                            if let subtddoc = HTML(html: subtd, encoding: .utf8) {
                                                
                                                if let rawStatus = subtddoc.at_css("strong"), let status = rawStatus.innerHTML {
                                                    submissionDic["status"] = status
                                                }
                                            }
                                        }
                                        
                                    } else if (index==3) {
                                        // First check if N/A
                                        if let subtd = td.innerHTML {
                                            let runtimeNAMatches = subtd.matches(regex: "N/A")
                                            if runtimeNAMatches.isEmpty {
                                                let runtimeNumMatches = subtd.matches(regex: "[0-9]+ ms")
                                                
                                                if runtimeNumMatches.count != 1 {
                                                    // THROW
                                                } else {
                                                    submissionDic["runtime"] = runtimeNumMatches[0]
                                                }
                                            } else {
                                                submissionDic["runtime"] = "N/A"
                                            }
                                        }
                                    }
                                    index += 1
                                }
                                
                                (self.submissionsDic[question_title_slug]!).append(submissionDic)
                            }
                        }
                    }
                } else {
                    completion(NSError(domain: "LTCore", code: -1, userInfo: ["error": LTCoreError.ResponseNoHTMLSubmissionList]), nil)
                }
                completion(nil, nil)
            }
            
        } else {
            completion(NSError(domain: "LTCore", code: -1, userInfo: ["error": LTCoreError.LocalCompletedQuestionsDicMalformed]), nil)
        }
    }
    
    func processSubmissionList(completion: @escaping (_: NSError?, _: Dictionary<String, AnyObject>?) -> Void) -> Void {
        
        for (question_title_slug, submissionDic) in submissionsDic {
            
            var submissionCounter = 1
            
            var completedRequestCount = 0
            
            for eachSubmission in submissionDic.reversed() {
                //print (questionId(titleSlug: question_title_slug)+question_title_slug+" "+eachSubmission["submission_id"]!)
                
                let question_id = self.questionId(titleSlug: question_title_slug)
                let question_title = self.questionTitle(questionId: question_id)
                let submission_id = eachSubmission[Constants.lcSubmissionIdKey]!
                let runtime = eachSubmission["runtime"]!
                let status = eachSubmission["status"]!
                
                
                // Check if submission_id is in database, if not add it later
                if (self.submissionIdInDatabase(submission_id)) {
                    print("skipping: "+submission_id)
                    submissionCounter += 1
                    return;
                }
                
                let folderName = question_id + " " + question_title
                let folderFullPath = self.gitRepoPath + folderName + "/"
                let fileFullPath = folderFullPath + "README.md"
                
                
                let fHandle = FileHandle.init(forWritingAtPath: fileFullPath)
                fHandle?.seekToEndOfFile()
                fHandle?.write(String(format: Constants.submissionRow, String(submissionCounter), status, runtime).data(using: String.Encoding.utf8)!)
                
                
                
                self.getSubmissionResult(questionId: question_id, questionTitle: question_title, submissionId: submission_id, submissionCounter: submissionCounter, completion: { (error, dic) in
                    
                    self.addSubmissionIdToDatabase(submission_id)
                    
                    completedRequestCount += 1
                    if (completedRequestCount == submissionCounter-1) {
                        completion(nil, nil)
                    }
                })
                
                submissionCounter += 1
            }
            
        }
        
    }
    
    func getSubmissionResult(questionId: String, questionTitle: String, submissionId: String, submissionCounter: Int, completion: @escaping (_: NSError?, _: Dictionary<String, AnyObject>?) -> Void) -> Void {
        
        let u = URL(string: String(format: Constants.submissionPageURL, submissionId))!
        let mutableUrlRequest = URLRequest.lcGetRequest(url: u, cookie: lcCookie, userAgent: Constants.lcUserAgent)
        
        Alamofire.request(mutableUrlRequest).responseString { response in
            if response.result.isSuccess {
                if let html = response.result.value {
                    let submissionCodeResults = html.matches(regex: "(?>(submissionCode: ))'[^']+'")
                    if submissionCodeResults.count == 1 {
                        let submissionCodeResult = submissionCodeResults[0]
                        let beg = submissionCodeResult.index(submissionCodeResult.startIndex, offsetBy: 17)
                        let end = submissionCodeResult.index(submissionCodeResult.endIndex, offsetBy: -2)
                        
                        // \u literals need to be converted
                        let trimmedSubmissionCodeResult = submissionCodeResult[beg...end]
                        
                        // Must use JS :/ sadly
                        let context = JSContext()
                        _ = context?.evaluateScript("var simpleOutput = function(value) {return value}")
                        let rawProcessedResult1 = context?.evaluateScript(String(format: "simpleOutput('%@')", trimmedSubmissionCodeResult))
                        
                        let processedResult1 = rawProcessedResult1?.toString()
                        
                        let processedResult2 = processedResult1?.replacingOccurrences(of: "\\r\\n", with: "\n")
                        
                        
                        // Save File
                        let folderName = questionId + " " + questionTitle
                        let folderFullPath = self.gitRepoPath + folderName + "/"
                        let fileFullPath = String(format: "%@%@.s%i.cpp",folderFullPath, questionId, submissionCounter)
                        
                        // Create folder if necessary
                        let manager = FileManager.default
                        do {
                            try manager.createDirectory(atPath: folderFullPath, withIntermediateDirectories: false, attributes: nil)
                        } catch {
                            
                        }
                        
                        do {
                            manager.createFile(atPath: fileFullPath, contents: nil, attributes: nil)
                            try processedResult2?.write(toFile: fileFullPath, atomically: false, encoding: String.Encoding.utf8)
                        } catch {
                            // BAD
                            print("Write data failed: ", questionTitle, " ", submissionCounter, " ", submissionId)
                        }
                        
                        
                    } else {
                        //PROBLEM
                        print("Response cannot find submissionCode: ", questionTitle, " ", submissionCounter, " ", submissionId)
                    }
                }
            } else {
                // PROBLEM
            }
        }
        
        
    }
    
}

extension URLRequest {
    static func lcGetRequest(url: URL, cookie: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        return request
    }
    
    static func lcGetRequest(url: URL, cookie: String, userAgent: String) -> URLRequest {
        var request = URLRequest.lcGetRequest(url: url, cookie: cookie)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}

extension String {
    func runAsCommand() -> String {
        let pipe = Pipe()
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", String(format:"%@", self)]
        task.standardOutput = pipe
        let file = pipe.fileHandleForReading
        task.launch()
        if let result = NSString(data: file.readDataToEndOfFile(), encoding: String.Encoding.utf8.rawValue) {
            return result as String
        }
        else {
            return "--- Error running command - Unable to initialize string from file data ---"
        }
    }
    
    // Stackoverflow: http://stackoverflow.com/questions/27880650/swift-extract-regex-matches
    func matches(regex: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: regex)
            let nsString = self as NSString
            let results = regex.matches(in: self, range: NSRange(location: 0, length: nsString.length))
            return results.map { nsString.substring(with: $0.range)}
        } catch let error {
            print("invalid regex: \(error.localizedDescription)")
            return []
        }
    }
}
