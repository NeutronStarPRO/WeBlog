import Cycles "mo:base/ExperimentalCycles";
import Principal "mo:base/Principal";
import Result "mo:base/Result";
import Option "mo:base/Option";
import Array "mo:base/Array";
import Debug "mo:base/Debug";
import Nat64 "mo:base/Nat64";
import List "mo:base/List";
import Time "mo:base/Time";
import Text "mo:base/Text";
import Trie "mo:base/Trie";
import Nat "mo:base/Nat";
import Prim "mo:prim";


shared({caller}) actor class StoreBlog(owner : Principal, new_canister_name : Text) = this {


    // ====================================================================================
    // ================================ ↓ about canister ↓ ================================
    // ====================================================================================


    private stable var canister_name : Text = new_canister_name;
    // owner可以添加或者转移，所以用var
    private stable var canister_owner = owner;

    // 展示这个canister的名字
    public shared query func get_canister_name() : async Text {
        return canister_name;
    };

    // 重命名
    public shared({caller}) func rename_canister(new_name : Text): async Bool {
        // assert(Principal.isAnonymous(caller) == false);
        assert(caller == owner);
        canister_name := new_name;
        return true;
    };

    // 展示这个canister的cycles余额
    public shared query func cycles_balance() : async Nat {
        return Cycles.balance();
    };

    // 接收cycles
    let limit = 1_000_000_000_000; // 1T cycles
    public func cycles_receive() : async { accepted : Nat64 } {
        // Cycles.available显示发送过来了多少cycles
        let available = Cycles.available();
        // Cycles.accept是接收函数，limit限制了一次最多接受的数量
        let accepted = Cycles.accept(Nat.min(available, limit));
        // 多出来的cycles原路返还
        { accepted = Nat64.fromNat(accepted) };
    };

    // 发送cycles
    // 用命令行给WeBlog canister发送cycles:
    // dfx canister call StoreBlog cycles_transfer "(func \"$(dfx canister id WeBlog)\".cycles_receive, 1_000_000_000_000)"
    // public func cycles_transfer(
    //     // 传入一个shared方法作为参数
    //     receiver: shared () -> async (),
    //     // 发送cycles数量
    //     amount : Nat
    // ) : async {
    //     refunded : Nat
    // } {
    //         Cycles.add(amount); // 把cycles添加进发送函数
    //         await receiver(); // 异步调用上面传进来的函数，等函数执行完再执行下一行
    //         // 如果对方没有接收全部的cycles返还回来，用Cycles.refunded查看
    //         { refunded = Cycles.refunded() };
    // };

    // 获取当前canister id
    public shared query func get_canister_id() : async Principal {
        return Principal.fromActor(this);
    };

    public shared query func get_memory_size() : async Nat {
        return Prim.rts_memory_size();
    };

    public shared query({ caller }) func whoami() : async Principal {
        return caller;
    };

    public shared({ caller }) func change_owner(other : Principal.Principal): async Bool {
        // assert(Principal.isAnonymous(caller) == false);
        assert(caller == owner);
        canister_owner := other;
        return true;
    };


    // ====================================================================================
    // ===================================== ↓ blog ↓ =====================================
    // ====================================================================================


    // 初始化生成存储7000个blog的数组，总共能存储7000篇blog
    private stable var _blogs : [var ?blog_record] = Array.init<?blog_record>(7000, null);

    // 定义blog的输入类型为text
    public type blog_text = {
        title : Text; // 少于50个字符
        blog : Text; // 规定少于15000个字符 long encodedURIcomponent string
    };

    // 定义blog的存储类型为blob
    public type blog_blob = {
        title : Blob;
        blog : Blob;
    };

    // 记录一个blog的信息存入canister
    public type blog_record = {
        blog_id : Nat;
        author : Principal;
        is_original : Bool;
        create_time : Int;
        blog : blog_blob;
    };

    // blog_return类型与blog_record类型基本一样，区别是有一个解码后的text文本blog
    public type blog_return = {
        blog_id : Nat;
        author : Principal;
        is_original : Bool;
        create_time : Int;
        blog : blog_text;
    };

    // 上传blog
    public shared({ caller }) func add_blog(blog : blog_text, is_original : Bool) : async Result.Result<Text, Text> {
        // assert(Principal.isAnonymous(caller) == false);
        assert(caller == owner);
        assert(check_valid_blog(caller, blog));

        var id = 0; // blog id 因为创建的数组是从0开始，所以这也是0

        for (x in _blogs.vals()) { // 遍历存blog的数组，找到空地存入新blog
            if (x == null) {
                let new_blog : blog_record = {
                    blog_id = id;
                    author = caller;
                    is_original = is_original;
                    blog = encode_blog(blog);
                    create_time = Time.now();
                };
                _blogs[id] := ?new_blog; // 存入blog数据
                return #ok(Nat.toText(id));
            };
            id += 1;
        };
        return #err("Ops! Out of storage space ~");
    };

    // 删除某篇blog
    public shared({ caller }) func delete_blog(blog_id : Nat) : async Result.Result<Text, Text> {
        // assert(Principal.isAnonymous(caller) == false);
        assert(caller == owner);

        let result = _blogs[blog_id];

        switch (result) {
            case (null) { return #err("Blog not found.") };
            case (?result) {
                _blogs[blog_id] := null;
                // 使用 # 可以连接字符串
                return #ok("Blog id: " # Nat.toText(blog_id) # " deleted.");
            };
        };
    };

    // 更新blog
    public shared({ caller }) func upgrade_blog(blog_id : Nat, blog : blog_text) : async Result.Result<Text, Text> {
        // assert(Principal.isAnonymous(caller) == false);
        assert(caller == owner); // 检查调用者是不是作者
        let result = _blogs[blog_id]; // 通过id查找存blog的数组里有没有这篇blog

        switch (result) {
            case (null) { return #err("Blog not found") }; // 没找着blog
            case (?result) {
                // 把找到的结果保留下来赋给upgrade_content，这样更新文章时只需要传入blog_id和blog内容即可
                let upgrade_blog_id = result.blog_id;
                let upgrade_author = result.author;
                let upgrade_is_original = result.is_original;
                let upgrade_create_time = result.create_time;

                let upgrade_content : blog_record = {
                    blog_id = upgrade_blog_id;
                    author = upgrade_author;
                    is_original = upgrade_is_original;
                    create_time = upgrade_create_time;
                    blog = encode_blog(blog);
                };
                _blogs[blog_id] := null; // 先清空原有的内容
                _blogs[blog_id] := ?upgrade_content; // 赋值更新blog
                return #ok("Upgarade success, blog id : " # Nat.toText(blog_id) # " .");
            };
        };
    };

    // 通过id查询某一个blog
    public query func get_blog(blog_id : Nat) : async Result.Result<blog_return, Text> {
        let result = _blogs[blog_id];

        switch (result) {
            case (null) { return #err("Blog not found.") };
            case (?result) {
                return #ok({
                    blog_id =  result.blog_id;
                    author = result.author;
                    is_original = result.is_original;
                    create_time = result.create_time;
                    blog = decode_blog(result.blog);
                });
            };
        };
    };

    // 获取这个canister里所有的blog
    public query func get_all_blogs() : async Result.Result<[?blog_record], ()> {
        return #ok(Array.freeze(_blogs));
    };


    // ====================================================================================
    // ============================== ↓ blog private func ↓ ===============================
    // ====================================================================================


    // 把blog数据从text编码为blob
    private func encode_blog(blog : blog_text) : blog_blob {
        return {
            title = Text.encodeUtf8(blog.title);
            blog = Text.encodeUtf8(blog.blog);
        };
    };

    // 把blog数据从blob解码为text
    private func decode_blog(blog : blog_blob) : blog_text {
        return {
            title = Option.unwrap(Text.decodeUtf8(blog.title));
            blog = Option.unwrap(Text.decodeUtf8(blog.blog));
        };
    };

    // 检查上传blog是否符合条件
    private func check_valid_blog(caller : Principal, blog : blog_text) : Bool {        
        // assert (Principal.isAnonymous(caller) == false); // 检查是否为匿名身份调用
        assert(blog.title.size() <= 50); // 标题限制50字符
        assert(blog.blog.size() <= 15000); // 每篇blog限制15000字符
        return true;
    };

};
