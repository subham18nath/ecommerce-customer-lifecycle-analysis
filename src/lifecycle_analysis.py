import pandas as pd
import numpy as np


def run_lifecycle_analysis(cust_path: str = "data/ecommerce_customers.csv",
                           orders_path: str = "data/ecommerce_orders.csv",
                           snapshot_str: str = "2026-10-31"):
    """Compute customer lifecycle stages, repeat conversion velocity, and CLV metrics."""
    df_cust = pd.read_csv(cust_path)
    df_orders = pd.read_csv(orders_path)

    snapshot_dt = pd.Timestamp(snapshot_str)
    df_orders["Order_Date_dt"] = pd.to_datetime(df_orders["Order_Date"])
    df_cust["Acq_Date_dt"] = pd.to_datetime(df_cust["Acquisition_Date"])

    # Aggregate customer-level lifecycle KPIs
    agg = df_orders.groupby("Customer_ID").agg(
        First_Order=("Order_Date_dt", "min"),
        Last_Order=("Order_Date_dt", "max"),
        Total_Orders=("Order_ID", "nunique"),
        Total_CLV_INR=("Order_Value_INR", "sum"),
        Avg_Order_Value_INR=("Order_Value_INR", "mean")
    ).reset_index()

    df = pd.merge(df_cust, agg, on="Customer_ID", how="left")
    df["Days_Since_Last_Order"] = (snapshot_dt - df["Last_Order"]).dt.days
    df["Tenure_Days"] = (snapshot_dt - df["Acq_Date_dt"]).dt.days

    def assign_stage(r):
        if r["Total_Orders"] == 1 and r["Tenure_Days"] <= 45:
            return "1. New / Onboarding (0-45d)"
        elif r["Total_Orders"] >= 8 and r["Days_Since_Last_Order"] <= 60:
            return "3. VIP Champions"
        elif r["Total_Orders"] >= 2 and r["Days_Since_Last_Order"] <= 75:
            return "2. Active Repeat / Loyal"
        elif r["Total_Orders"] >= 2 and 75 < r["Days_Since_Last_Order"] <= 135:
            return "4. At-Risk (Lapsing)"
        elif r["Total_Orders"] == 1 and r["Tenure_Days"] > 45:
            return "5. One-Time Churned"
        else:
            return "6. Churned Repeaters"

    df["Lifecycle_Stage"] = df.apply(assign_stage, axis=1)

    # Time to 2nd order velocity
    df_orders_sorted = df_orders.sort_values(["Customer_ID", "Order_Date_dt"])
    df_orders_sorted["Days_Between"] = df_orders_sorted.groupby("Customer_ID")["Order_Date_dt"].diff().dt.days
    second_orders = df_orders_sorted[df_orders_sorted["Order_Sequence"] == 2]

    repeat_rate = (df["Total_Orders"] >= 2).mean() * 100
    median_days_2nd = second_orders["Days_Between"].median()

    print("=" * 64)
    print("E-COMMERCE CUSTOMER LIFECYCLE SUMMARY (2,500 CUSTOMERS)")
    print("=" * 64)
    print(f"Total Customers Acquired : {len(df):,}")
    print(f"Total Orders Placed      : {len(df_orders):,}")
    print(f"Repeat Purchase Rate     : {repeat_rate:.1f}%")
    print(f"Median Time to 2nd Order : {median_days_2nd:.0f} days")
    print(f"Overall Avg CLV (INR)    : INR {df['Total_CLV_INR'].mean():,.2f}")
    print("=" * 64)

    summary = df.groupby("Lifecycle_Stage").agg(
        Customers=("Customer_ID", "count"),
        Avg_Orders=("Total_Orders", "mean"),
        Avg_CLV_INR=("Total_CLV_INR", "mean"),
        Total_Revenue_INR=("Total_CLV_INR", "sum")
    ).round(2)
    print("\nLifecycle Stage Breakdown:\n", summary)


if __name__ == "__main__":
    run_lifecycle_analysis()
