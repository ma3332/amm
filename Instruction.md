# Xem walkthrough: https://ethereum.org/en/developers/tutorials/uniswap-v2-annotated-code/

# Explanation in details: https://betterprogramming.pub/uniswap-v2-in-depth-98075c826254

# Về nguyên lý hoạt động của AMM thì phải xem ở link ở trên. Nó có giải thích tại sao sàn giao dịch lại có thể hoạt động mà ko cần trung gian

1. Cần hiểu về LP Token (bản chất nó chính là ERC20 token nhưng cần xem nó được sinh ra như thế nào)

# Hướng dẫn qua về cách chạy

1, Deploy OurOwnFactory.sol
2, Chạy hàm pairCodeHash() hoặc getByteCode() của OurOwnFactory.sol
3, Thay dòng số 39 của file UniswapV2Library.sol bằng kết quả thu được ở bước 2 (cái này quan trọng, ko là đếch chạy được tiếp đâu nhé)
4, Deploy OurOwnRouter.sol // Tất cả các hoạt động tương tác với hệ thống sau này sẽ thông qua Router
4.1 Mỗi lần chạy hàm \_addLiquidity() của OurOwnRouter.sol thì sẽ tạo ra một LP Token.
4.2 Nếu input của tokenA và tokenB giống nhau cho mỗi lần gọi hàm \_addLiquidity() thì sẽ tạo ra các LP token address giống nhau và số lượng sẽ được quyết định ở công thức của AMM
4.3 Nếu input của tokenA và tokenB khác nhau cho mỗi lần gọi hàm \_addLiquidity() thì sẽ tạo ra các LP token address khác nhau. Đây được gọi là người tạo LP đầu tiên, thường sẽ là bên nhà phát triển của Token đó.
4.4 Lưu ý trong trường hợp tạo LP trong đó có 1 token là Native Coin (vd: ETH, Matic ...) thì để cho dễ dàng quản lý, hệ thống sẽ sử dụng WETH, WMATIC. Wrap ETH là gì, tạo ra như thế nào, ý nghĩa ra làm sao thì phải tìm hiểu. (mở rộng, tạo WETH ntn?)
5 Hệ thống này có 1 vài nhược điểm như sau:
5.1 Tên của LP token là giống nhau mặc dù address khác nhau, sẽ dễ gây confuse cho người dùng (tại sao?)
5.2 Chưa có lợi nhuận hoặc staking LP Token để thu hút người dùng (cải thiện ntn?)
5.3 Uniswap ERC20 vô dụng với cái hệ thống này vãi, nên người dùng không thấy có động lực để mua token UNISWAP, giá cao là bọn nó tự đẩy (tại sao lại vậy và cải thiện ntn?)
5.4 Các hệ thống DEX tạo ra Arbitrage ->> không fair đối với tất cả người dùng (cải thiện ntn?)

--> yêu cầu tạm thời là test được hệ thống với webjs hoặc framework như brownie, hardhat.
--> Tạo một web3 đơn giản để test hệ thống trên
--> tích hợp với project hiện tại
--> tìm cách khắc phục nhược điểm

# Even though AMMs don’t update their prices based on incoming real-world information (no price feed), traders can still expect the price quoted by an AMM to closely track the global market price because of continuous arbitrage.

# Impermanent loss for liquidity providers is the change in dollar terms of their total stake in a given pool versus just holding the assets

# Number of Initial Issued LP tokens = (No of Token_1 \* No of Token_2) ^ 0.5

# Big Pair (ex: ETH-WBTC) should be created by big players (investors) only as if the pair is created, no one else can create the same pair.
