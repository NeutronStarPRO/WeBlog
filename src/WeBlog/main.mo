import Cycles "mo:base/ExperimentalCycles";
import Principal "mo:base/Principal";
import Array "mo:base/Array";
import Nat64 "mo:base/Nat64";
import RBT "mo:base/RBTree";
import Nat "mo:base/Nat";
import Prim "mo:prim";

import StoreBlog "./blog";
import Types "./types";


// 这个canister的名字在dfx.json里，叫 WeBlog 还有package.json里第11行也得改
actor WeBlog {
    // 记录创建的canister个数
    private stable var store_blogs_index : Nat = 0;
    // 用红黑树存储所有创建的canister
    private let store_blogs = RBT.RBTree<Nat, Principal>(Nat.compare);
    private let IC : Types.ICActor = actor "aaaaa-aa";
    private let cycles_for_canister = 1_000_000_000_000; // 每个创建的canister分配1T cycles

    public type canister_info = {
        canister_id : Principal;
        id : Nat;
    };

    // 查看principal id
    public shared query({ caller }) func whoami() : async Principal {
        return caller;
    };

    // 查看canister id
    public shared query({ caller }) func get_canister_id() : async Principal {
        return Principal.fromActor(WeBlog);
    };

    // 展示这个canister的cycles余额
    public shared query func cycles_balance() : async Nat {
        return Cycles.balance();
    };

    // 查看已经创建了多少个canister
    public query func get_canister_count(): async Text {
        return (Nat.toText(store_blogs_index));
    };

    // 查看存储空间
    public query func get_memory_size(): async Nat {
        return Prim.rts_memory_size();
    };

    // limit限制了一次最多接受的数量
    let limit = 1_000_000_000_000; // 1T cycles
    // 接收cycles
    public func cycles_receive() : async { accepted : Nat64 } {
        // Cycles.available显示发送过来了多少cycles
        let available = Cycles.available();
        // Cycles.accept是接收函数，
        let accepted = Cycles.accept(Nat.min(available, limit));
        // 多出来的cycles原路返还
        { accepted = Nat64.fromNat(accepted) };
    };

    // 发送cycles
    // 用命令行给WeBlog canister发送cycles:
    // dfx canister call StoreBlog cycles_transfer "(func \"$(dfx canister id WeBlog)\".cycles_receive, 1_000_000_000_000)"
    public func cycles_transfer(
        // 传入一个shared方法作为参数
        receiver : shared () -> async (),
        // 发送cycles数量
        amount : Nat
    ) : async {
        refunded : Nat
    } {
            Cycles.add(amount); // 把cycles添加进发送函数
            await receiver(); // 异步调用上面传进来的函数，等函数执行完再执行下一行
            // 如果对方没有接收全部的cycles返还回来，用Cycles.refunded查看
            { refunded = Cycles.refunded() };
    };

    // 创建canister的函数，可以传入一个canister的名字，成功后返回创建的canister id
    public shared({ caller }) func create_store_blog(new_canister_name : Text) : async canister_info {
        Cycles.add(cycles_for_canister);
        let store_blog = await StoreBlog.StoreBlog(caller, new_canister_name);
        let principal = Principal.fromActor(store_blog);

        await IC.update_settings({
            canister_id = principal;
            settings = {
                freezing_threshold = ?2_000_000;
                controllers = ?[principal]; // controller是这个新canister自己
                memory_allocation = ?0;
                compute_allocation = ?0;
            }
        });
        // 把刚创建的canister的principal id存入红黑树
        store_blogs.put(store_blogs_index, principal);
        store_blogs_index += 1;
        let canister_info = { canister_id = principal;id = store_blogs_index; };
    };

    // 显示某个canister的controller
    public func get_controllers(canister_id : Principal) : async [Principal] {
        let status = await IC.canister_status({ canister_id = canister_id });
        return status.settings.controllers;
    };

};